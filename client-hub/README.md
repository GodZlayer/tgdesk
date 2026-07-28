# Descontinuado

O Hub deixou de ser um aplicativo e um build separados.

Desde a versão 0.2.5 existe um único `tgdesk.exe`. O instalador escolhe entre
Cliente e Técnico em runtime. No modo Técnico, o Hub inclui a aba **Cliente**
e o agente Host permanece ativo para que outro técnico possa acessar a estação.

O código ativo está em `client-rustdesk-src/flutter/lib/tgdesk/`.
