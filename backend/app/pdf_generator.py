"""
pdf_generator.py — Generazione PDF per valutazioni cliniche.

Supporta sia scale con scoring psicometrico (San Martín: radar chart, QoL, percentili)
sia scale semplici (POS: bar chart orizzontale).
"""
import io
from datetime import datetime, timezone
from typing import List, Dict, Optional

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import cm
from reportlab.lib.colors import Color, HexColor, white, black
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle,
    Image as RLImage, HRFlowable, PageBreak
)
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT

# ─── Palette colori tema ────────────────────────────────────────────────────
PRIMARY    = HexColor('#1A237E')
SECONDARY  = HexColor('#FFB74D')
ACCENT     = HexColor('#81C784')
DARK_TEXT  = HexColor('#2D3748')
LIGHT_GREY = HexColor('#F3F8FF')
MID_GREY   = HexColor('#718096')
BORDER     = HexColor('#E8EEF8')
RED_MEAN   = HexColor('#E57373')

DOMAIN_COLORS = [
    '#1A237E', '#E53935', '#43A047', '#FB8C00',
    '#8E24AA', '#00ACC1', '#3949AB', '#F4511E',
]

FASCIA_COLORS = {
    "Molto Basso": '#D32F2F',
    "Basso":       '#F57C00',
    "Medio":       '#FBC02D',
    "Alto":        '#7CB342',
    "Molto Alto":  '#388E3C',
}


def _wrap_label(text: str, max_chars: int = 16) -> str:
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


# ─── Grafico radar per San Martín ───────────────────────────────────────────

def _make_radar_chart(
    domains: List[dict],
    score_min: int = 0,
    score_max: int = 20,
    mean_ref: int = 10,
) -> io.BytesIO:
    """
    Crea un grafico radar (tela di ragno) a 8 assi con:
    - Profilo paziente (blu navy pieno + fill)
    - Linea media normativa (rossa tratteggiata)
    - Anelli concentrici con etichette
    """
    labels = [d["codice"] for d in domains]
    patient_values = [d.get("punteggio_standard") or 0 for d in domains]
    mean_values = [mean_ref] * len(labels)
    n = len(labels)

    angles = np.linspace(0, 2 * np.pi, n, endpoint=False).tolist()
    angles += angles[:1]

    patient_vals = patient_values + patient_values[:1]
    mean_vals = mean_values + mean_values[:1]

    fig, ax = plt.subplots(figsize=(8, 8), subplot_kw=dict(polar=True), dpi=150)
    fig.patch.set_facecolor('#F8FBFF')
    ax.set_facecolor('#F8FBFF')

    ax.set_theta_offset(np.pi / 2)
    ax.set_theta_direction(-1)

    ax.set_xticks(angles[:-1])
    ax.set_xticklabels(labels, fontsize=12, fontweight='bold', color='#2D3748')

    ax.set_ylim(score_min, score_max)
    ax.set_yticks([0, 4, 8, 12, 16, 20])
    ax.set_yticklabels(['0', '4', '8', '12', '16', '20'],
                        fontsize=8, color='#9E9E9E')
    ax.yaxis.grid(True, color='#DDE7F8', linewidth=0.8)
    ax.xaxis.grid(True, color='#DDE7F8', linewidth=0.8)
    ax.spines['polar'].set_color('#90A4AE')
    ax.spines['polar'].set_linewidth(1.2)

    ax.fill(angles, patient_vals, color='#1A237E', alpha=0.10)
    ax.plot(angles, patient_vals, 'o-', linewidth=2.5, markersize=7,
            color='#1A237E', markerfacecolor='white', markeredgewidth=2,
            markeredgecolor='#1A237E', label='Paziente', zorder=5)

    ax.plot(angles, mean_vals, '--', linewidth=1.8, color='#E57373',
            label=f'Media ({mean_ref})', alpha=0.8)

    ax.legend(loc='upper right', bbox_to_anchor=(1.25, 1.12),
              fontsize=9, framealpha=0.9, edgecolor='#E8EEF8')

    ax.set_title('Profilo Punteggi Standard', fontsize=14,
                 fontweight='bold', color='#2D3748', pad=24)

    plt.tight_layout()
    buf = io.BytesIO()
    plt.savefig(buf, format='png', bbox_inches='tight', facecolor='#F8FBFF', dpi=150)
    plt.close(fig)
    buf.seek(0)
    return buf


# ─── Grafico a barre (fallback POS) ─────────────────────────────────────────

def _make_bar_chart(domains: List[dict], score_min: int = 6, score_max: int = 18) -> io.BytesIO:
    labels = [_wrap_label(d['etichetta']) for d in domains]
    scores = [d["punteggio_totale"] for d in domains]
    n = len(labels)
    colors = DOMAIN_COLORS[:n]

    fig, ax = plt.subplots(figsize=(10, max(3.5, n * 0.6 + 1.2)), dpi=140)
    fig.patch.set_facecolor('#F8FBFF')
    ax.set_facecolor('#F8FBFF')

    y = np.arange(n)
    bars = ax.barh(y, scores, color=colors, height=0.6, zorder=3)

    ax.axvline(score_min, color='#E57373', linewidth=1.2, linestyle='--',
               alpha=0.7, label=f'Min ({score_min})')
    ax.axvline(score_max, color='#81C784', linewidth=1.2, linestyle='--',
               alpha=0.7, label=f'Max ({score_max})')

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


# ─── Helper tabelle ─────────────────────────────────────────────────────────

def _make_table(headers: list, rows: list, col_widths: list,
                header_color, style_extras: list = None) -> Table:
    data = [headers] + rows
    t = Table(data, colWidths=col_widths)
    base_style = [
        ('FONTNAME',     (0, 0), (-1, 0), 'Helvetica-Bold'),
        ('FONTSIZE',     (0, 0), (-1, -1), 9),
        ('BACKGROUND',   (0, 0), (-1, 0), header_color),
        ('TEXTCOLOR',    (0, 0), (-1, 0), white),
        ('VALIGN',       (0, 0), (-1, -1), 'MIDDLE'),
        ('ROWBACKGROUNDS', (0, 1), (-1, -1), [LIGHT_GREY, white]),
        ('GRID',         (0, 0), (-1, -1), 0.3, BORDER),
        ('TOPPADDING',   (0, 0), (-1, -1), 5),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
        ('LEFTPADDING',  (0, 0), (-1, -1), 6),
    ]
    if style_extras:
        base_style.extend(style_extras)
    t.setStyle(TableStyle(base_style))
    return t


def _safe_text(value: object, fallback: str = "—") -> str:
    if value is None:
        return fallback
    text = str(value).strip()
    return text if text else fallback


def _format_pdf_date(value: object) -> str:
    if isinstance(value, datetime):
        return value.strftime("%d/%m/%Y")
    try:
        return datetime.fromisoformat(str(value)).strftime("%d/%m/%Y")
    except Exception:
        text = str(value).strip()
        return text[:10] if text else "—"


def _make_label_value_paragraph(
    label: str,
    value: object,
    styles,
    value_fallback: str = "—",
) -> Paragraph:
    safe_value = _safe_text(value, value_fallback)
    return Paragraph(
        f"<b>{label}</b> {safe_value}",
        ParagraphStyle(
            f"{label}_cell",
            parent=styles["BodyText"],
            fontName="Helvetica",
            fontSize=9,
            leading=12,
            textColor=DARK_TEXT,
        ),
    )


def _make_san_martin_meta_table(
    evaluation: dict,
    patient: dict,
    scale: dict,
    styles,
) -> Table:
    patient_name = f"{patient.get('nome', '')} {patient.get('cognome', '')}".strip() or "—"
    clinical_bits = []
    if patient.get("altezza"):
        clinical_bits.append(f"{patient['altezza']} cm")
    if patient.get("peso"):
        clinical_bits.append(f"{patient['peso']} kg")

    notes_value = _safe_text(patient.get("note"), "")
    if len(notes_value) > 140:
        notes_value = f"{notes_value[:137]}..."

    rows = [
        [
            _make_label_value_paragraph("Paziente:", patient_name, styles),
            _make_label_value_paragraph("Data:", _format_pdf_date(evaluation.get("data_compilazione")), styles),
            _make_label_value_paragraph("Scala:", scale.get("nome"), styles),
            _make_label_value_paragraph("Operatore:", evaluation.get("nome_operatore"), styles),
        ],
        [
            _make_label_value_paragraph("Intervistato/a:", evaluation.get("nome_intervistato"), styles),
            _make_label_value_paragraph("Anno:", evaluation.get("anno"), styles),
            _make_label_value_paragraph("ID valutazione:", _safe_text(evaluation.get("id_valutazione"))[:12], styles),
            _make_label_value_paragraph(
                "Dati clinici:",
                " / ".join(clinical_bits) if clinical_bits else "—",
                styles,
            ),
        ],
    ]

    if notes_value:
        rows.append([
            _make_label_value_paragraph("Note cliniche:", notes_value, styles, ""),
            Paragraph("", styles["BodyText"]),
            Paragraph("", styles["BodyText"]),
            Paragraph("", styles["BodyText"]),
        ])

    table_style = [
        ('BACKGROUND', (0, 0), (-1, -1), white),
        ('ROWBACKGROUNDS', (0, 0), (-1, -1), [LIGHT_GREY, white]),
        ('BOX', (0, 0), (-1, -1), 0.6, BORDER),
        ('INNERGRID', (0, 0), (-1, -1), 0.3, BORDER),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('LEFTPADDING', (0, 0), (-1, -1), 8),
        ('RIGHTPADDING', (0, 0), (-1, -1), 8),
        ('TOPPADDING', (0, 0), (-1, -1), 7),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 7),
    ]
    if notes_value:
        table_style.append(('SPAN', (0, 2), (-1, 2)))

    table = Table(rows, colWidths=[4.0 * cm, 4.0 * cm, 4.7 * cm, 4.1 * cm])
    table.setStyle(TableStyle(table_style))
    return table


def _make_qv_summary_table(analysis: dict, styles) -> Table:
    summary_title = Paragraph(
        "Riepilogo Psicometrico San Martín",
        ParagraphStyle(
            "QvSummaryTitle",
            parent=styles["BodyText"],
            fontSize=12,
            leading=14,
            textColor=white,
            fontName="Helvetica-Bold",
        ),
    )
    fascia_value = _safe_text(analysis.get("fascia_qv"))
    fascia_color = FASCIA_COLORS.get(fascia_value, '#FFFFFF')

    rows = [
        [
            summary_title,
            Paragraph(
                f"<b>Indice QV</b><br/><font size='18'>{_safe_text(analysis.get('indice_qv'))}</font>",
                ParagraphStyle(
                    "QvMetricValue",
                    parent=styles["BodyText"],
                    fontName="Helvetica",
                    fontSize=10,
                    leading=13,
                    alignment=TA_CENTER,
                    textColor=white,
                ),
            ),
            Paragraph(
                f"<b>Percentile</b><br/><font size='18'>{_safe_text(analysis.get('percentile'))}</font>",
                ParagraphStyle(
                    "QvPercentileValue",
                    parent=styles["BodyText"],
                    fontName="Helvetica",
                    fontSize=10,
                    leading=13,
                    alignment=TA_CENTER,
                    textColor=HexColor('#AED581'),
                ),
            ),
        ],
        [
            Paragraph(
                f"Somma punteggi standard: <b>{_safe_text(analysis.get('somma_punteggi_standard'))}</b>",
                ParagraphStyle(
                    "QvSecondaryMetric",
                    parent=styles["BodyText"],
                    fontSize=10,
                    leading=12,
                    textColor=white,
                    fontName="Helvetica",
                ),
            ),
            Paragraph(
                f"Fascia: <font color='{fascia_color}'><b>{fascia_value}</b></font>",
                ParagraphStyle(
                    "QvFasciaMetric",
                    parent=styles["BodyText"],
                    fontSize=10,
                    leading=12,
                    textColor=white,
                    fontName="Helvetica",
                    alignment=TA_CENTER,
                ),
            ),
            Paragraph("", styles["BodyText"]),
        ],
    ]

    table = Table(rows, colWidths=[8.2 * cm, 4.5 * cm, 4.7 * cm])
    table.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, -1), PRIMARY),
        ('BOX', (0, 0), (-1, -1), 0, PRIMARY),
        ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ('LEFTPADDING', (0, 0), (-1, -1), 8),
        ('RIGHTPADDING', (0, 0), (-1, -1), 8),
        ('TOPPADDING', (0, 0), (-1, -1), 7),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 7),
        ('SPAN', (1, 1), (2, 1)),
    ]))
    return table


def _make_san_martin_domain_table(analysis: dict) -> Table:
    headers = ["Codice", "Dominio", "P. Grezzo", "P. Std", "Percentile", "Fascia"]
    rows = []
    for domain in analysis.get("domini", []):
        fascia = _safe_text(domain.get("fascia"))
        fascia_color_hex = FASCIA_COLORS.get(fascia, '#2D3748')
        fascia_color = HexColor(fascia_color_hex)

        std_val = domain.get("punteggio_standard")
        std_text = _safe_text(std_val)

        std_cell = Paragraph(
            f"<font color='{fascia_color_hex}'><b>{std_text}</b></font>",
            ParagraphStyle(
                f"std_{domain.get('codice', '')}",
                fontSize=10,
                leading=12,
                fontName="Helvetica-Bold",
                alignment=TA_CENTER,
            ),
        )

        perc_val = domain.get("percentile_dominio")
        perc_text = f"{perc_val}°" if perc_val is not None else "—"

        rows.append([
            _safe_text(domain.get("codice")),
            _safe_text(domain.get("etichetta")),
            _safe_text(domain.get("punteggio_diretto")),
            std_cell,
            perc_text,
            Paragraph(
                fascia,
                ParagraphStyle(
                    f"fascia_{domain.get('codice', '')}",
                    fontSize=8,
                    leading=10,
                    fontName="Helvetica-Bold",
                    textColor=fascia_color,
                    alignment=TA_CENTER,
                ),
            ),
        ])

    table = _make_table(
        headers=headers,
        rows=rows,
        col_widths=[1.5 * cm, 5.5 * cm, 1.8 * cm, 1.5 * cm, 1.7 * cm, 2.5 * cm],
        header_color=PRIMARY,
        style_extras=[
            ('ALIGN', (0, 0), (0, -1), 'CENTER'),
            ('ALIGN', (2, 0), (-1, -1), 'CENTER'),
            ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
        ],
    )
    return table


# ─── Generazione PDF completo ────────────────────────────────────────────────

def generate_evaluation_pdf(
    evaluation: dict,
    patient: dict,
    scale: dict,
    domains: List[dict],
    analysis: Optional[dict] = None,
) -> bytes:
    buf = io.BytesIO()
    doc = SimpleDocTemplate(
        buf,
        pagesize=A4,
        leftMargin=1.8 * cm,
        rightMargin=1.8 * cm,
        topMargin=1.4 * cm,
        bottomMargin=1.4 * cm,
    )

    styles = getSampleStyleSheet()
    story = []

    # ── Stili personalizzati ────────────────────────────────────────────────
    title_style = ParagraphStyle(
        'CustomTitle', parent=styles['Title'],
        fontSize=22, textColor=DARK_TEXT, spaceAfter=4, fontName='Helvetica-Bold',
    )
    subtitle_style = ParagraphStyle(
        'Subtitle', parent=styles['Normal'],
        fontSize=12, textColor=MID_GREY, spaceAfter=10, fontName='Helvetica',
    )
    section_header = ParagraphStyle(
        'SectionHeader', parent=styles['Normal'],
        fontSize=12, textColor=DARK_TEXT, fontName='Helvetica-Bold',
        spaceBefore=12, spaceAfter=6,
    )

    has_analysis = analysis is not None and analysis.get("indice_qv") is not None
    scala_nome = scale.get("nome", "")
    normalized_scale_name = str(scala_nome).lower().replace(" ", "").replace("-", "")
    is_sanmartin = (
        analysis is not None and (
            "sanmartin" in normalized_scale_name or
            analysis.get("indice_qv") is not None or
            analysis.get("fascia_qv") is not None
        )
    )

    # ── Header ─────────────────────────────────────────────────────────────
    story.append(Paragraph("Report Valutativo", title_style))
    story.append(HRFlowable(width="100%", thickness=1, color=BORDER, spaceBefore=4, spaceAfter=10))

    # ── Info scala ─────────────────────────────────────────────────────────
    if is_sanmartin:
        scale_meta = []
        if scale.get("anno"):
            scale_meta.append(f"Anno: {scale['anno']}")
        if scale_meta:
            story.append(Paragraph("Scala San Martín", section_header))
            for line in scale_meta:
                story.append(Paragraph(line, ParagraphStyle(
                    'ScaleMeta', parent=styles['Normal'],
                    fontSize=8, textColor=MID_GREY, fontName='Helvetica',
                    spaceAfter=1,
                )))
            story.append(Spacer(1, 0.15 * cm))

    # ── Info paziente / valutazione ─────────────────────────────────────────
    if is_sanmartin:
        story.append(_make_san_martin_meta_table(evaluation, patient, scale, styles))
    else:
        nome_paziente = f"{patient.get('nome', '')} {patient.get('cognome', '')}"
        data_str = _format_pdf_date(evaluation.get("data_compilazione", datetime.now(timezone.utc)))
        meta_data = [
            ["Paziente:", nome_paziente, "Data:", data_str],
            ["Scala:", scala_nome, "Operatore:", evaluation.get("nome_operatore", "-")],
            ["Intervistato/a:", evaluation.get("nome_intervistato", "-"),
             "Anno:", str(evaluation.get("anno", "-"))],
            ["ID Valutazione:", evaluation.get("id_valutazione", "-")[:8] + "…", "", ""],
        ]
        meta_table = Table(meta_data, colWidths=[2.6*cm, 6.3*cm, 2.6*cm, 5.8*cm])
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
        ]))
        story.append(meta_table)
    story.append(Spacer(1, 0.2 * cm))

    # ── Riepilogo QV (solo San Martín) ───────────────────────────────────────
    if is_sanmartin and analysis is not None:
        story.append(_make_qv_summary_table(analysis, styles))
        story.append(Spacer(1, 0.25 * cm))

    # ── Grafico ─────────────────────────────────────────────────────────────
    story.append(Paragraph("Profilo dei Punteggi", section_header))

    if is_sanmartin and analysis is not None:
        chart_domains = analysis.get("domini", [])
        chart_buf = _make_radar_chart(chart_domains)
        chart_img = RLImage(chart_buf, width=10.2 * cm, height=10.2 * cm)
    else:
        chart_buf = _make_bar_chart(domains)
        chart_img = RLImage(chart_buf, width=17 * cm, height=6.5 * cm)

    story.append(chart_img)
    story.append(Spacer(1, 0.2 * cm))

    # ── Legenda fasce ───────────────────────────────────────────────────────
    if is_sanmartin and analysis is not None:
        story.append(Paragraph("Fasce Interpretative (Punteggi Standard)",
                               ParagraphStyle('LegendTitle', parent=styles['Normal'],
                                              fontSize=9, textColor=MID_GREY,
                                              fontName='Helvetica-Bold', spaceAfter=4)))
        fasce_data = [[
            Paragraph("Molto Basso<br/>1–4",
                      ParagraphStyle('FB', parent=styles['Normal'], fontSize=7,
                                     textColor=HexColor('#D32F2F'), fontName='Helvetica-Bold',
                                     alignment=TA_CENTER, leading=9)),
            Paragraph("Basso<br/>5–7",
                      ParagraphStyle('FB', parent=styles['Normal'], fontSize=7,
                                     textColor=HexColor('#F57C00'), fontName='Helvetica-Bold',
                                     alignment=TA_CENTER, leading=9)),
            Paragraph("Medio<br/>8–12",
                      ParagraphStyle('FB', parent=styles['Normal'], fontSize=7,
                                     textColor=HexColor('#FBC02D'), fontName='Helvetica-Bold',
                                     alignment=TA_CENTER, leading=9)),
            Paragraph("Alto<br/>13–15",
                      ParagraphStyle('FB', parent=styles['Normal'], fontSize=7,
                                     textColor=HexColor('#7CB342'), fontName='Helvetica-Bold',
                                     alignment=TA_CENTER, leading=9)),
            Paragraph("Molto Alto<br/>16–20",
                      ParagraphStyle('FB', parent=styles['Normal'], fontSize=7,
                                     textColor=HexColor('#388E3C'), fontName='Helvetica-Bold',
                                     alignment=TA_CENTER, leading=9)),
        ]]
        legend_table = Table(fasce_data, colWidths=[3.2*cm]*5)
        legend_table.setStyle(TableStyle([
            ('VALIGN',       (0, 0), (-1, -1), 'MIDDLE'),
            ('ALIGN',        (0, 0), (-1, -1), 'CENTER'),
            ('BACKGROUND',   (0, 0), (-1, -1), LIGHT_GREY),
            ('TOPPADDING',   (0, 0), (-1, -1), 4),
            ('BOTTOMPADDING',(0, 0), (-1, -1), 4),
            ('ROUNDEDCORNERS', [6]),
        ]))
        story.append(legend_table)
        story.append(Spacer(1, 0.25 * cm))
    # ── Tabella riepilogo domìni ─────────────────────────────────────────────
    story.append(PageBreak())
    story.append(Paragraph("Riepilogo per Dominio", section_header))

    if is_sanmartin and analysis is not None:
        domain_table = _make_san_martin_domain_table(analysis)
    else:
        domain_headers = ["Cod.", "Dominio", "Punteggio Totale", "N° Domande"]
        domain_rows = [
            [d["codice"], d["etichetta"], str(d["punteggio_totale"]), str(d["num_domande"])]
            for d in domains
        ]
        col_widths = [1.5*cm, 7*cm, 4*cm, 3*cm]
        style_extras = [
            ('ALIGN', (2, 0), (3, -1), 'CENTER'),
        ]

        domain_table = _make_table(
            domain_headers, domain_rows, col_widths, PRIMARY, style_extras
        )
    story.append(domain_table)
    story.append(Spacer(1, 0.5 * cm))

    # ── Tabella dettaglio risposte ───────────────────────────────────────────
    story.append(Paragraph("Dettaglio Risposte", section_header))

    if is_sanmartin and analysis is not None:
        # Build map for San Martin questions
        questions_map = {}
        if scale and "domini" in scale:
            for domain in scale["domini"]:
                for q in domain.get("domande", []):
                    q_code = q.get("codice")
                    if q_code:
                        questions_map[q_code] = {
                            "testo": q.get("testo", ""),
                            "opzioni": {
                                opt.get("punteggio"): opt.get("etichetta", "")
                                for opt in q.get("opzioni", [])
                            }
                        }

        resp_headers = ["Codice", "Domanda", "Risposta", "Nota"]
        resp_rows = []
        cell_style = ParagraphStyle('RespCell', parent=styles['Normal'], fontSize=8, leading=10)
        cell_style_bold = ParagraphStyle('RespCellBold', parent=styles['Normal'], fontSize=8, leading=10, fontName='Helvetica-Bold')

        for r in evaluation.get("risposte", []):
            q_code = r.get("codice_domanda", "-")
            punteggio = r.get("punteggio", "-")
            nota = r.get("nota") or ""
            
            q_info = questions_map.get(q_code)
            q_text = q_info["testo"] if q_info else "—"
            
            opt_label = ""
            try:
                p_val = int(punteggio)
            except ValueError:
                p_val = None
                
            if q_info and p_val is not None:
                opt_label = q_info["opzioni"].get(p_val, "")
            
            if opt_label:
                risposta_display = f"{opt_label} ({punteggio})"
            else:
                risposta_display = str(punteggio)

            resp_rows.append([
                Paragraph(q_code, cell_style_bold),
                Paragraph(q_text, cell_style),
                Paragraph(risposta_display, cell_style),
                Paragraph(nota, cell_style)
            ])
            
        # Total printable width is 17.4 * cm
        col_widths = [1.8*cm, 7.2*cm, 3.8*cm, 4.6*cm]
        resp_table = _make_table(
            resp_headers, resp_rows, col_widths, SECONDARY,
            [('VALIGN', (0, 0), (-1, -1), 'TOP')]
        )
    else:
        # Fallback/standard style for other scales
        resp_headers = ["Codice", "Punteggio", "Nota"]
        resp_rows = [
            [
                r.get("codice_domanda", "-"),
                str(r.get("punteggio", "-")),
                r.get("nota") or "",
            ]
            for r in evaluation.get("risposte", [])
        ]
        resp_table = _make_table(
            resp_headers, resp_rows, [2.5*cm, 2.5*cm, 14.5*cm], SECONDARY,
            [('ALIGN', (1, 0), (1, -1), 'CENTER'),
             ('WORDWRAP', (2, 0), (2, -1), True)]
        )
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
