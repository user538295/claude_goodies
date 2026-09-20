"""SmtpEmailClient — INFRASTRUCTURE adapter. Flat-sprawl fixture for arch-17."""

import smtplib


class SmtpEmailClient:
    """Sends mail over SMTP — concrete infrastructure I/O."""

    def __init__(self, host: str) -> None:
        self._host = host

    def send(self, to: str, body: str) -> None:
        with smtplib.SMTP(self._host) as smtp:
            smtp.sendmail("shop@example.com", to, body)
