FROM python:3.12-alpine

ENV PIP_DISABLE_PIP_VERSION_CHECK=1

RUN pip install --no-cache-dir --root-user-action=ignore flask gunicorn

COPY app.py /app.py

ENTRYPOINT ["gunicorn", "--bind", "0.0.0.0:9090", "--workers", "2", "app:app"]
