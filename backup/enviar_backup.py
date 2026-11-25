"""Backup semanal do Mr. Control por e-mail.

Roda no GitHub Actions. Lê o banco pela conexão direta (segredo DATABASE_URL),
gera um arquivo .json.gz com tudo (sem senhas e sem sessões) e envia aos
administradores ativos que têm e-mail cadastrado na aba Pessoas.

O repositório é público: este script NUNCA imprime dados, e-mails ou o
conteúdo do backup no log, e não grava nada no GitHub. Só imprime contagens.
"""
import gzip
import json
import os
import smtplib
import ssl
import sys
from datetime import datetime, timedelta, timezone
from email.message import EmailMessage

import psycopg

BRT = timezone(timedelta(hours=-3))
LIMITE_ANEXO = 20 * 1024 * 1024  # Gmail aceita até 25 MB; folga para a codificação do anexo


def falha(msg):
    print("ERRO: " + msg)
    sys.exit(1)


def main():
    url = os.environ.get("DATABASE_URL", "").strip()
    usuario = os.environ.get("GMAIL_USUARIO", "").strip()
    senha = os.environ.get("GMAIL_SENHA_APP", "").replace(" ", "").strip()
    if not url:
        falha("segredo DATABASE_URL não configurado.")
    if not usuario or not senha:
        falha("segredos GMAIL_USUARIO / GMAIL_SENHA_APP não configurados.")

    try:
        with psycopg.connect(url, connect_timeout=30, prepare_threshold=None) as con:
            cur = con.cursor()
            cur.execute("select public.backup_completo(), public.backup_destinatarios(), public.backup_resumo()")
            dados, destinatarios, resumo = cur.fetchone()
    except Exception as e:  # não imprime a URL nem detalhes que possam conter dados
        falha("não consegui ler o banco (" + type(e).__name__ + "). Confira o DATABASE_URL.")

    if not destinatarios:
        falha("nenhum administrador ativo com e-mail. Cadastre o e-mail na aba Pessoas do app.")

    agora = datetime.now(BRT)
    nome = "mr-control-backup-" + agora.strftime("%Y-%m-%d") + ".json.gz"
    bruto = json.dumps(dados, ensure_ascii=False, separators=(",", ":"), default=str).encode("utf-8")
    anexo = gzip.compress(bruto, compresslevel=9)
    grande = len(anexo) > LIMITE_ANEXO

    linhas = []
    for f in resumo:
        ult = f.get("ultimo_envio")
        ult = datetime.fromisoformat(ult).astimezone(BRT).strftime("%d/%m/%Y") if ult else "—"
        linhas.append("• %s%s: %d planilha(s), %d trato(s); último envio %s" % (
            f["nome"], "" if f.get("ativa") else " (inativa)", f["abas"], f["tratos"], ult))

    corpo = [
        "Olá,",
        "",
        "Segue o backup semanal do Mr. Control (" + agora.strftime("%d/%m/%Y %H:%M") + ").",
        "",
        *linhas,
        "",
        "Totais: %d fazenda(s), %d planilha(s), %d pessoa(s), %d registro(s) de atividade." % (
            len(dados["fazendas"]), len(dados["abas"]), len(dados["pessoas"]), len(dados["registro"])),
        "",
    ]
    if grande:
        corpo += ["ATENÇÃO: o backup ficou com %.1f MB, acima do limite de anexo do Gmail. "
                  "Ele NÃO foi anexado. Avise quem mantém o app para dividir o envio." % (len(anexo) / 1048576), ""]
    else:
        corpo += ["O anexo " + nome + " (%.0f KB) tem todas as planilhas, ajustes, históricos e o registro." % (len(anexo) / 1024),
                  "Ele não contém senhas. Guarde este e-mail: com o anexo é possível reconstruir os dados.", ""]
    corpo += ["— Mr. Control (envio automático, não responda)"]

    msg = EmailMessage()
    msg["Subject"] = "Mr. Control — backup semanal " + agora.strftime("%d/%m/%Y")
    msg["From"] = "Mr. Control <" + usuario + ">"
    msg["To"] = usuario
    msg["Bcc"] = ", ".join(destinatarios)  # cada adm não vê o e-mail dos outros
    msg.set_content("\n".join(corpo))
    if not grande:
        msg.add_attachment(anexo, maintype="application", subtype="gzip", filename=nome)

    host = os.environ.get("SMTP_HOST", "smtp.gmail.com")
    porta = int(os.environ.get("SMTP_PORTA", "465"))
    try:
        if porta == 465:
            with smtplib.SMTP_SSL(host, porta, context=ssl.create_default_context(), timeout=60) as s:
                s.login(usuario, senha)
                s.send_message(msg)
        else:  # só para teste local
            with smtplib.SMTP(host, porta, timeout=60) as s:
                s.send_message(msg)
    except smtplib.SMTPAuthenticationError:
        falha("o Gmail recusou o login. Confira GMAIL_USUARIO e GMAIL_SENHA_APP (senha de app, 16 letras).")
    except Exception as e:
        falha("não consegui enviar o e-mail (" + type(e).__name__ + ").")

    try:
        with psycopg.connect(url, connect_timeout=30, prepare_threshold=None) as con:
            con.execute("select public.registrar_backup(%s, %s)", (len(destinatarios), len(anexo)))
    except Exception:
        print("aviso: e-mail enviado, mas não consegui anotar no registro.")

    print("ok: %d destinatário(s), %d fazenda(s), %d planilha(s), anexo %d KB%s" % (
        len(destinatarios), len(dados["fazendas"]), len(dados["abas"]), max(1, -(-len(anexo) // 1024)),
        " (NÃO anexado: grande demais)" if grande else ""))
    if grande:
        sys.exit(1)


if __name__ == "__main__":
    main()
