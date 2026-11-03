# Spec: Untrusted diagram text

## System design

```flow
Client <script> (new) -> Gateway & Co : "send" <b>now</b>
Gateway & Co -> Client <script> : reply
```

```sequence
Client -> Gateway : get <id> & "flag"
Gateway --> Client : 200 <ok>
Client -> Client : retry & log
```
