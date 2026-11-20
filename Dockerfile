# Scan-Dienst (Linux-Container). Bauen:
#   docker compose up -d --build
# Aktualisieren (Debian-Pakete und Basis-Image): docker compose build --pull && docker compose up -d
FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get upgrade -y \
 && apt-get install -y --no-install-recommends \
      ocrmypdf tesseract-ocr-deu tesseract-ocr-osd poppler-utils python3-venv ca-certificates tzdata \
 && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /app/requirements.txt
RUN python3 -m venv /app/venv \
 && /app/venv/bin/pip install --no-cache-dir -r /app/requirements.txt

COPY dienst.py /app/dienst.py
# Bauzeitpunkt fuer die Update-Erinnerung (dienst.py meldet, wenn das Image zu alt ist)
RUN /app/venv/bin/python -m py_compile /app/dienst.py && date -Iseconds > /app/gebaut

ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 TZ=Europe/Berlin HOME=/tmp TMPDIR=/tmp
# Nie als root; docker-compose.yml setzt den Benutzer aus .env
USER 65534:65534
ENTRYPOINT ["/app/venv/bin/python", "/app/dienst.py"]
