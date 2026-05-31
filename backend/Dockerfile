FROM python:3.11-slim

# Variables de entorno para comportamiento predecible
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH=/root/.local/bin:$PATH \
    PYTHONPATH=/app

WORKDIR /app

# Instalar dependencias del sistema necesarias para paquetes Python
# Separadas en una capa para aprovechar el cache cuando cambian solo los requisitos
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       build-essential \
       gcc \
       libpq-dev \
       curl \
    && rm -rf /var/lib/apt/lists/*

# Copiar primero solo requirements para aprovechar cache de Docker
COPY backend/requirements.txt ./requirements.txt

# Actualizar pip e instalar dependencias Python
RUN pip install --upgrade pip setuptools wheel \
    && pip install --no-cache-dir -r requirements.txt

# Copiar el resto del código de la aplicación
COPY backend/ .

EXPOSE 8000

# Healthcheck: asume que la app expone /health
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8000/health || exit 1

# Comando por defecto: ejecutar uvicorn
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
