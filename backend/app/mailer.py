"""Envoi d'e-mails par relais SMTP (décision D-08 : compte de messagerie de l'entreprise).

Si le relais n'est pas configuré, rien n'est envoyé : l'administrateur transmet lui-même
le lien d'invitation affiché dans l'application.
"""

import logging
import smtplib
import ssl
from email.message import EmailMessage

from .config import get_settings

log = logging.getLogger("lamaalam.mailer")


def send_mail(to: str, subject: str, body: str) -> bool:
    settings = get_settings()
    if not settings.smtp_configured:
        log.warning("Relais SMTP non configuré : e-mail non envoyé (%s)", subject)
        return False
    msg = EmailMessage()
    msg["From"] = settings.smtp_from
    msg["To"] = to
    msg["Subject"] = subject
    msg.set_content(body)
    try:
        with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=20) as smtp:
            smtp.starttls(context=ssl.create_default_context())
            if settings.smtp_user and settings.smtp_password:
                smtp.login(settings.smtp_user, settings.smtp_password)
            smtp.send_message(msg)
        return True
    except (OSError, smtplib.SMTPException):
        log.exception("Échec de l'envoi de l'e-mail « %s »", subject)
        return False


def send_invitation(to: str, full_name: str, organization: str, url: str, hours: int) -> bool:
    body = (
        f"Bonjour {full_name},\n\n"
        f"{organization} vous invite à rejoindre son espace sur l'application LAMAALAM.\n\n"
        f"Pour créer votre mot de passe, ouvrez ce lien (valable {hours} heures, utilisable une seule fois) :\n"
        f"{url}\n\n"
        "Si vous n'attendiez pas cette invitation, ignorez ce message.\n"
    )
    return send_mail(to, f"Invitation — {organization}", body)
