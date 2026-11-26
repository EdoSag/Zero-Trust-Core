# zt_assist

Lets a Zero-Trust app ask ZT Assist, the suite's private AI, to summarize,
rewrite, proofread, translate or title a text, or to follow the app's own
instruction. The model runs inside ZT Assist on the same phone: the text goes
from one app to the other and nowhere else, and nothing is sent to a server.
See the "Ask ZT Assist" section of the repository README.

Apps need no manifest changes: the plugin's manifest lets the app see
ZT Assist. Android only; on other platforms `availability()` answers
`unavailable`.

The plugin only talks to an app named `dev.sagron.zerotrustassist` that is
signed with the same key as the app asking, and ZT Assist only answers apps
signed with its own key. The message numbers and field names in
`ZtAssistPlugin.java` are a contract with `AssistService.java` in
Zero-Trust-Assist: change them in both.
