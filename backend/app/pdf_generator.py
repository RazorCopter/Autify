"""
pdf_generator.py
Generazione PDF per valutazioni POS con grafici (lineare o barre).
"""
import io
from datetime import datetime, timezone
from typing import List, Dict

import matplotlib
matplotlib.use('Agg')  # Backend non-interattivo per server
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np

from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import cm
from reportlab.lib.colors import Color, HexColor, white, black
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle,
    Image as RLImage, HRFlowable
)
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT

# ─── Palette colori tema ────────────────────────────────────────────────────
PRIMARY    = HexColor('#64B5F6')   # azzurro
SECONDARY  = HexColor('#FFB74D')   # arancio
ACCENT     = HexColor('#81C784')   # verde
DARK_TEXT  = HexColor('#2D3748')
LIGHT_GREY = HexColor('#F3F8FF')
MID_GREY   = HexColor('#718096')
BORDER     = HexColor('#E8EEF8')

DOMAIN_COLORS = [
    '#64B5F6', '#FFB74D', '#81C784', '#CE93D8',
    '#E57373', '#4FC3F7', '#AED581', '#FF8A65',
]

# ─── Aggregazione domìni ────────────────────────────────────────────────────
def aggregate_domains(risposte: list, domini_map: Dict[str, str]) -> List[dict]:
    """
    Raggruppa le risposte per prefisso dominio e calcola la somma.
    risposte: lista di dict {"codice_domanda": str, "punteggio": int, ...}
    """
    aggregated: Dict[str, dict] = {}
    for cod, label in domini_map.items():
        aggregated[cod] = {"codice": cod, "etichetta": label, "punteggio_totale": 0, "num_domande": 0}

    for r in risposte:
        codice = r.get("codice_domanda", "")
        for prefix in sorted(domini_map.keys(), key=len, reverse=True):
            if codice.upper().startswith(prefix.upper()):
                aggregated[prefix]["punteggio_totale"] += r.get("punteggio", 0)
                aggregated[prefix]["num_domande"] += 1
                break

    return list(aggregated.values())


def _wrap_label(text: str, max_chars: int = 14) -> str:
    """Divide un'etichetta su due righe se supera max_chars."""
    if len(text) <= max_chars:
        return text
    if ' ' in text:
        mid = len(text) // 2
        best = mid
        for i, ch in enumerate(text):
            if ch == ' ':
                if abs(i - mid) < abs(best - mid):
                    best = i
        return text[:best] + '\n' + text[best + 1:]
    mid = len(text) // 2
    return text[:mid] + '\n' + text[mid:]


def _make_bar_chart(domains: List[dict], score_min: int = 6, score_max: int = 18) -> io.BytesIO:
    labels   = [_wrap_label(d['etichetta']) for d in domains]
    scores   = [d["punteggio_totale"] for d in domains]
    n = len(labels)
    colors   = DOMAIN_COLORS[:n]

    fig, ax = plt.subplots(figsize=(10, max(3.5, n * 0.6 + 1.2)), dpi=140)
    fig.patch.set_facecolor('#F8FBFF')
    ax.set_facecolor('#F8FBFF')

    y = np.arange(n)
    bars = ax.barh(y, scores, color=colors, height=0.6, zorder=3)

    # Linee di riferimento verticali
    ax.axvline(score_min, color='#E57373', linewidth=1.2, linestyle='--', alpha=0.7, label=f'Min ({score_min})')
    ax.axvline(score_max, color='#81C784', linewidth=1.2, linestyle='--', alpha=0.7, label=f'Max ({score_max})')

    for bar, score in zip(bars, scores):
        ax.text(bar.get_width() + 0.2, bar.get_y() + bar.get_height() / 2,
                str(score), va='center', ha='left', fontsize=10,
                fontweight='bold', color='#2D3748')

    ax.set_yticks(y)
    ax.set_yticklabels(labels, fontsize=10, color='#2D3748')
    ax.set_xlabel('Punteggio', fontsize=10, color='#718096')
    ax.set_xlim(0, score_max * 1.18)
    ax.invert_yaxis()
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    ax.spines['left'].set_color('#E8EEF8')
    ax.spines['bottom'].set_color('#E8EEF8')
    ax.grid(axis='x', color='#E8EEF8', linestyle='--', linewidth=0.8)
    ax.legend(loc='lower right', fontsize=9)
    ax.set_title('Istogramma Comparato dei Punteggi per Dominio', fontsize=13,
                 fontweight='bold', color='#2D3748', pad=12)

    plt.tight_layout()
    buf = io.BytesIO()
    plt.savefig(buf, format='png', bbox_inches='tight', facecolor='#F8FBFF')
    plt.close(fig)
    buf.seek(0)
    return buf


# ─── Generazione PDF completo ────────────────────────────────────────────────
def generate_evaluation_pdf(
    evaluation: dict,
    patient: dict,
    scale: dict,
    domains: List[dict],
) -> bytes:
    buf = io.BytesIO()
    doc = SimpleDocTemplate(
        buf,
        pagesize=A4,
        leftMargin=1.8 * cm,
        rightMargin=1.8 * cm,
        topMargin=2 * cm,
        bottomMargin=2 * cm,
    )

    styles = getSampleStyleSheet()
    story = []

    # ── Stili personalizzati ────────────────────────────────────────────────
    title_style = ParagraphStyle(
        'CustomTitle',
        parent=styles['Title'],
        fontSize=22,
        textColor=DARK_TEXT,
        spaceAfter=4,
        fontName='Helvetica-Bold',
    )
    subtitle_style = ParagraphStyle(
        'Subtitle',
        parent=styles['Normal'],
        fontSize=12,
        textColor=MID_GREY,
        spaceAfter=16,
        fontName='Helvetica',
    )
    section_header_style = ParagraphStyle(
        'SectionHeader',
        parent=styles['Normal'],
        fontSize=11,
        textColor=DARK_TEXT,
        fontName='Helvetica-Bold',
        spaceBefore=18,
        spaceAfter=6,
    )
    label_style = ParagraphStyle(
        'Label',
        parent=styles['Normal'],
        fontSize=9,
        textColor=MID_GREY,
        fontName='Helvetica',
    )
    normal_style = ParagraphStyle(
        'Body',
        parent=styles['Normal'],
        fontSize=10,
        textColor=DARK_TEXT,
        fontName='Helvetica',
    )

    # ── Header ─────────────────────────────────────────────────────────────
    story.append(Paragraph("AutAnalysis", title_style))
    story.append(Paragraph("Report di Valutazione Clinica", subtitle_style))
    story.append(HRFlowable(width="100%", thickness=1, color=BORDER, spaceAfter=14))

    # ── Info paziente / valutazione ─────────────────────────────────────────
    nome_paziente = f"{patient.get('nome', '')} {patient.get('cognome', '')}"
    data_str = evaluation.get("data_compilazione", datetime.now(timezone.utc))
    if isinstance(data_str, datetime):
        data_str = data_str.strftime("%d/%m/%Y")
    else:
        try:
            data_str = datetime.fromisoformat(str(data_str)).strftime("%d/%m/%Y")
        except Exception:
            data_str = str(data_str)[:10]

    meta_data = [
        ["Paziente:", nome_paziente,     "Data:",      data_str],
        ["Scala:",    scale.get("nome", ""), "Operatore:", evaluation.get("nome_operatore", "-")],
        ["Intervistato/a:", evaluation.get("nome_intervistato", "-"), "Anno:", str(evaluation.get("anno", "-"))],
        ["ID Valutazione:", evaluation.get("id_valutazione", "-")[:8] + "…", "", ""],
    ]
    meta_table = Table(meta_data, colWidths=[2.8*cm, 7*cm, 2.8*cm, 7*cm])
    meta_table.setStyle(TableStyle([
        ('FONTNAME',    (0, 0), (-1, -1), 'Helvetica'),
        ('FONTSIZE',    (0, 0), (-1, -1), 9),
        ('FONTNAME',    (0, 0), (0, -1), 'Helvetica-Bold'),
        ('FONTNAME',    (2, 0), (2, -1), 'Helvetica-Bold'),
        ('TEXTCOLOR',   (0, 0), (0, -1), DARK_TEXT),
        ('TEXTCOLOR',   (2, 0), (2, -1), DARK_TEXT),
        ('TEXTCOLOR',   (1, 0), (1, -1), MID_GREY),
        ('TEXTCOLOR',   (3, 0), (3, -1), MID_GREY),
        ('VALIGN',      (0, 0), (-1, -1), 'MIDDLE'),
        ('ROWBACKGROUNDS', (0, 0), (-1, -1), [LIGHT_GREY, white]),
        ('TOPPADDING',  (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
        ('LEFTPADDING', (0, 0), (-1, -1), 6),
        ('ROUNDEDCORNERS', [4]),
    ]))
    story.append(meta_table)
    story.append(Spacer(1, 0.4 * cm))

    # ── Grafico ─────────────────────────────────────────────────────────────
    story.append(Paragraph("Profilo dei Punteggi Aggregati", section_header_style))

    chart_buf = _make_bar_chart(domains)

    chart_img = RLImage(chart_buf, width=17 * cm, height=6.5 * cm)
    story.append(chart_img)
    story.append(Spacer(1, 0.4 * cm))

    # ── Tabella aggregata domìni ─────────────────────────────────────────────
    story.append(Paragraph("Riepilogo per Dominio", section_header_style))

    domain_headers = ["Cod.", "Dominio", "Punteggio Totale", "N° Domande"]
    domain_rows = [domain_headers] + [
        [d["codice"], d["etichetta"], str(d["punteggio_totale"]), str(d["num_domande"])]
        for d in domains
    ]
    col_widths = [1.5*cm, 7*cm, 4*cm, 3*cm]
    domain_table = Table(domain_rows, colWidths=col_widths)
    domain_table.setStyle(TableStyle([
        ('FONTNAME',     (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE',     (0, 0), (-1, -1), 9),
        ('BACKGROUND',   (0, 0), (-1, 0), PRIMARY),
        ('TEXTCOLOR',    (0, 0), (-1, 0), white),
        ('ALIGN',        (2, 0), (3, -1), 'CENTER'),
        ('VALIGN',       (0, 0), (-1, -1), 'MIDDLE'),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [LIGHT_GREY, white]),
        ('GRID',         (0, 0), (-1, -1), 0.3, BORDER),
        ('TOPPADDING',   (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
        ('LEFTPADDING',  (0, 0), (-1, -1), 6),
    ]))
    story.append(domain_table)
    story.append(Spacer(1, 0.5 * cm))

    # ── Tabella dettaglio risposte ───────────────────────────────────────────
    story.append(Paragraph("Dettaglio Risposte", section_header_style))

    resp_headers = ["Codice", "Punteggio", "Nota"]
    resp_rows = [resp_headers] + [
        [
            r.get("codice_domanda", "-"),
            str(r.get("punteggio", "-")),
            r.get("nota") or "",
        ]
        for r in evaluation.get("risposte", [])
    ]
    resp_table = Table(resp_rows, colWidths=[2.5*cm, 2.5*cm, 14.5*cm])
    resp_table.setStyle(TableStyle([
        ('FONTNAME',      (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE',      (0, 0), (-1, -1), 8.5),
        ('BACKGROUND',    (0, 0), (-1, 0), SECONDARY),
        ('TEXTCOLOR',     (0, 0), (-1, 0), white),
        ('ALIGN',         (1, 0), (1, -1), 'CENTER'),
        ('VALIGN',        (0, 0), (-1, -1), 'MIDDLE'),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [LIGHT_GREY, white]),
        ('GRID',          (0, 0), (-1, -1), 0.3, BORDER),
        ('TOPPADDING',    (0, 0), (-1, -1), 4),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 4),
        ('LEFTPADDING',   (0, 0), (-1, -1), 6),
        ('WORDWRAP',      (2, 0), (2, -1), True),
    ]))
    story.append(resp_table)

    # ── Footer ──────────────────────────────────────────────────────────────
    story.append(Spacer(1, 0.8 * cm))
    story.append(HRFlowable(width="100%", thickness=0.5, color=BORDER))
    story.append(Paragraph(
        f"Generato da AutAnalysis il {datetime.now(timezone.utc).strftime('%d/%m/%Y %H:%M')} UTC",
        ParagraphStyle('Footer', parent=styles['Normal'], fontSize=8,
                       textColor=MID_GREY, fontName='Helvetica', alignment=TA_RIGHT)
    ))

    doc.build(story)
    return buf.getvalue()
