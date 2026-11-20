#!/usr/bin/env python3
import os,sys,json,datetime
args=sys.argv[1:]
if args[:3] == ["--python","3.13","chroma-mcp"]:
    with open('<HOME>/.local/state/claude-mem-retention/20261120/shim-hits.jsonl',"a") as f:f.write(json.dumps({"utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"tool":"chroma-mcp","constraint":"pydantic<2.11"})+"\n")
    args=["--with","pydantic<2.11",*args]
os.execv('<HOME>/.local/bin/uvx',['<HOME>/.local/bin/uvx',*args])
