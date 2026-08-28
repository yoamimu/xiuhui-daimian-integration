FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN groupadd --system --gid 10001 activation \
    && useradd --system --uid 10001 --gid activation --home-dir /app activation \
    && mkdir -p /app /data \
    && chown activation:activation /app /data

WORKDIR /app
COPY activation-server/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY --chown=activation:activation activation_server /app/activation_server

USER activation
EXPOSE 8787
CMD ["gunicorn", "--workers", "2", "--threads", "2", "--timeout", "30", "--bind", "0.0.0.0:8787", "--access-logfile", "-", "--error-logfile", "-", "activation_server.wsgi:app"]
