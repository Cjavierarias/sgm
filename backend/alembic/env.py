import os
import sys
from logging.config import fileConfig

from alembic import context
from dotenv import load_dotenv
from sqlalchemy import engine_from_config, pool


# 1. Cargar .env desde la raíz de backend
load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))

# 2. Agregar backend al path para que `from app.models.base import Base` funcione.
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

# 3. Configurar Alembic
config = context.config

# 4. Obtener DATABASE_URL y convertirlo a sync para migraciones
#    Alembic debe usar un driver síncrono como `postgresql://...`.
database_url = os.getenv("DATABASE_URL", "")
if database_url:
    sync_url = database_url.replace("+asyncpg", "")
    config.set_main_option("sqlalchemy.url", sync_url)

# 5. Configurar logs
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# 6. Importar metadata desde los modelos
from app.models.base import Base  # noqa: E402

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    context.configure(
        url=config.get_main_option("sqlalchemy.url"),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )

    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
        )

        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
