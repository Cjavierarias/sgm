"""
Servicio de email para SGM.

Envía invitaciones a colaboradores y notificaciones por email.
Usa SMTP con TLS. En modo desarrollo puede simular el envío (log only).

Variables de entorno:
  SMTP_HOST          → host del servidor SMTP (ej: smtp.gmail.com)
  SMTP_PORT          → puerto (587 para TLS, 465 para SSL)
  SMTP_USER          → usuario SMTP (email remitente)
  SMTP_PASSWORD      → contraseña o app password
  SMTP_FROM          → email remitente (default: SMTP_USER)
  SMTP_FROM_NAME     → nombre remitente (default: "SGM — BSA Consultora")
  SMTP_ENABLED       → "true" para enviar, "false" para solo log (default: false)
  FRONTEND_URL       → URL del frontend para links de invitación
"""
from __future__ import annotations

import logging
import os
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from typing import Optional

logger = logging.getLogger(__name__)

SMTP_HOST       = os.getenv("SMTP_HOST", "")
SMTP_PORT       = int(os.getenv("SMTP_PORT", "587"))
SMTP_USER       = os.getenv("SMTP_USER", "")
SMTP_PASSWORD   = os.getenv("SMTP_PASSWORD", "")
SMTP_FROM       = os.getenv("SMTP_FROM", SMTP_USER)
SMTP_FROM_NAME  = os.getenv("SMTP_FROM_NAME", "SGM — BSA Consultora")
SMTP_ENABLED    = os.getenv("SMTP_ENABLED", "false").lower() == "true"
FRONTEND_URL    = os.getenv("FRONTEND_URL", "http://localhost:8080")


def _build_message(to_email: str, subject: str, html_body: str) -> MIMEMultipart:
    msg = MIMEMultipart("alternative")
    msg["From"]    = f"{SMTP_FROM_NAME} <{SMTP_FROM}>"
    msg["To"]      = to_email
    msg["Subject"] = subject
    msg.attach(MIMEText(html_body, "html", "utf-8"))
    return msg


def send_email(to_email: str, subject: str, html_body: str) -> bool:
    """
    Envía un email. Retorna True si se envió correctamente.
    Si SMTP_ENABLED=false, solo loguea y retorna True (modo desarrollo).
    """
    if not SMTP_ENABLED:
        logger.info("[EMAIL-DEV] Para: %s | Asunto: %s", to_email, subject)
        logger.info("[EMAIL-DEV] Body: %s", html_body[:200])
        return True

    if not SMTP_HOST or not SMTP_USER or not SMTP_PASSWORD:
        logger.error("SMTP no configurado. Set SMTP_HOST, SMTP_USER, SMTP_PASSWORD.")
        return False

    try:
        msg = _build_message(to_email, subject, html_body)
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=30) as server:
            server.starttls()
            server.login(SMTP_USER, SMTP_PASSWORD)
            server.sendmail(SMTP_FROM, [to_email], msg.as_string())
        logger.info("Email enviado a %s: %s", to_email, subject)
        return True
    except Exception as exc:
        logger.error("Error enviando email a %s: %s", to_email, exc)
        return False


def send_invitation_email(
    to_email: str,
    inviter_name: str,
    company_name: str,
    token: str,
    roles: Optional[list[str]] = None,
) -> bool:
    """Envía el email de invitación a un colaborador."""
    accept_url = f"{FRONTEND_URL}/#/accept-invitation?token={token}"
    roles_label = ", ".join(roles) if roles else "colaborador"

    html = f"""
    <html>
    <body style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
        <div style="background: linear-gradient(135deg, #0077B6, #005F8E); padding: 30px; border-radius: 12px 12px 0 0;">
            <h1 style="color: white; margin: 0; font-size: 24px;">SGM — BSA Consultora</h1>
            <p style="color: #B8E0F0; margin: 5px 0 0 0;">Sistema de Gestión de Mantenimiento</p>
        </div>
        <div style="background: #F0F4F8; padding: 30px; border-radius: 0 0 12px 12px;">
            <h2 style="color: #1A2E44; margin-top: 0;">¡Has sido invitado!</h2>
            <p style="color: #1A2E44; font-size: 16px; line-height: 1.5;">
                <strong>{inviter_name}</strong> te ha invitado a unirte a
                <strong>{company_name}</strong> en SGM como
                <strong>{roles_label}</strong>.
            </p>
            <p style="color: #5A7184; font-size: 14px;">
                SGM es una plataforma de gestión de mantenimiento industrial donde podrás:
            </p>
            <ul style="color: #5A7184; font-size: 14px;">
                <li>Ver y gestionar órdenes de trabajo</li>
                <li>Acceder al inventario de repuestos</li>
                <li>Consultar planes de mantenimiento</li>
                <li>Colaborar con tu equipo</li>
            </ul>
            <div style="text-align: center; margin: 30px 0;">
                <a href="{accept_url}"
                   style="background: #2D9F5E; color: white; padding: 14px 32px;
                          text-decoration: none; border-radius: 8px; font-weight: bold;
                          display: inline-block; font-size: 16px;">
                    Aceptar invitación
                </a>
            </div>
            <p style="color: #5A7184; font-size: 12px; text-align: center;">
                O copiá este enlace: {accept_url}<br>
                Esta invitación vence en 7 días.
            </p>
            <hr style="border: none; border-top: 1px solid #D8E3ED; margin: 20px 0;">
            <p style="color: #5A7184; font-size: 12px;">
                Si no esperabas esta invitación, podés ignorar este email.<br>
                © BSA Consultora — Sistema de Gestión de Mantenimiento
            </p>
        </div>
    </body>
    </html>
    """
    return send_email(to_email, "Invitación a SGM — BSA Consultora", html)
