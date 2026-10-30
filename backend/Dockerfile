FROM python:3.11.14-slim-bookworm@sha256:65a93d69fa75478d554f4ad27c85c1e69fa184956261b4301ebaf6dbb0a3543d

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 MPLCONFIGDIR=/tmp/matplotlib
RUN groupadd --gid 10001 autify && useradd --uid 10001 --gid autify --create-home autify
WORKDIR /app

COPY requirements.txt requirements.lock ./

RUN pip install --no-cache-dir --require-hashes -r requirements.txt

ARG CACHE_BUST=1
RUN echo "Cache bust: $CACHE_BUST"

COPY ./app ./app

USER 10001:10001

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
