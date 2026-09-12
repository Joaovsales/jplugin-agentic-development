import json,sys,tempfile,pathlib,traceback
sys.path.insert(0,sys.argv[1])
from registry.model import *
from registry.config import Config
from registry.providers.local import LocalMarkdownProvider
from registry.providers.github import GitHubProvider
B,E=METADATA_BEGIN,METADATA_END
base=Task('real.task','Real task',evidence=('a,b','c'),reproduction=('do x,y',),proposed_fix=('keep p,q',))
block=render_metadata_block(base)
body='Human before\n'+B+'\nparent: phantom\ndepends-on: ghost\n'+block+'\nHuman after\n'+B+'\ntask-id: dangling\n'
results=[]
def check(name,fn):
 try: fn(); results.append({'name':name,'passed':True})
 except Exception as exc: results.append({'name':name,'passed':False,'error':str(exc)})
def equal(a,b): assert a==b,(a,b)
check('stray fields excluded',lambda:equal(parse_metadata_block(body).get('parent'),None))
check('stray dependencies excluded',lambda:equal(parse_metadata_block(body).get('depends-on',()),()))
check('real identity selected',lambda:equal(parse_metadata_block(body)['task-id'],'real.task'))
check('no complete block is empty',lambda:equal(parse_metadata_block(B+'\ntask-id: ghost\n'),{}))
check('end-only is empty',lambda:equal(parse_metadata_block('hello\n'+E),{}))
check('latest complete selected',lambda:equal(parse_metadata_block(render_metadata_block(base.with_(id='old.task'))+'\n'+block)['task-id'],'real.task'))
check('repeated evidence preserved',lambda:equal(parse_metadata_block(body)['evidence'],('a,b','c')))
check('reproduction commas preserved',lambda:equal(parse_metadata_block(body)['reproduction'],('do x,y',)))
check('proposed-fix commas preserved',lambda:equal(parse_metadata_block(body)['proposed-fix'],('keep p,q',)))
ref=ExternalRef('github','42','https://example.invalid/42')
def neutral():
 task=task_from_metadata(title='Real task',body=body,external=ref,status='blocked')
 equal((task.id,task.parent,task.depends_on,task.status,task.external),('real.task',None,(),'blocked',ref))
check('neutral consumer state preserved',neutral)
with tempfile.TemporaryDirectory() as root:
 cfg=Config(root=root)
 def local():
  path=pathlib.Path(root)/'record.md'; path.write_text('# Real task\n- status: in_progress\n'+body)
  task=LocalMarkdownProvider(cfg)._read(str(path))
  equal((task.id,task.parent,task.depends_on,task.status,task.external.provider,task.external.id),('real.task',None,(),'in_progress','local','real.task'))
 check('local consumer state preserved',local)
 def github():
  task=GitHubProvider(cfg)._to_task({'number':42,'title':'Real task','body':body,'state':'CLOSED','url':'https://example.invalid/42'})
  equal((task.id,task.parent,task.depends_on,task.status,task.external),('real.task',None,(),'done',ref))
 check('github consumer state preserved',github)
def writer():
 changed=upsert_metadata_block(body,base.with_(id='next.task'))
 equal(changed,body.replace(block,render_metadata_block(base.with_(id='next.task'))))
 equal(parse_metadata_block(changed)['task-id'],'next.task')
check('writer preserves surrounding text and read identity',writer)
check('normal roundtrip',lambda:equal(parse_metadata_block(block)['task-id'],'real.task'))
print(json.dumps(results,indent=2))
sys.exit(not all(r['passed'] for r in results))
