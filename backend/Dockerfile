# syntax=docker/dockerfile:1
# Image de l'API LAMAALAM (Python, licence PSF ; dépendances : OPEN_SOURCE_LICENSE_REGISTER.md)
FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app

COPY requirements.txt .
# Certificat d'autorité facultatif (réseau d'entreprise qui inspecte le HTTPS) :
#   docker build --secret id=pip_ca,src=/chemin/ca.crt …
# Sans ce secret, rien ne change ; il n'est jamais copié dans l'image.
RUN --mount=type=secret,id=pip_ca,required=false \
    if [ -s /run/secrets/pip_ca ]; then export PIP_CERT=/run/secrets/pip_ca; fi; \
    pip install --no-cache-dir -r requirements.txt

COPY alembic.ini .
COPY migrations ./migrations
COPY app ./app

RUN useradd --system --uid 10001 lamaalam \
    && mkdir -p /var/lib/lamaalam/files \
    && chown lamaalam:lamaalam /var/lib/lamaalam/files
# Le volume des fichiers hérite de ce propriétaire à sa création.
VOLUME /var/lib/lamaalam/files
USER lamaalam

EXPOSE 8000
HEALTHCHECK --interval=15s --timeout=5s --retries=5 \
    CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/api/v1/health', timeout=4).status == 200 else 1)"]
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips", "*"]
