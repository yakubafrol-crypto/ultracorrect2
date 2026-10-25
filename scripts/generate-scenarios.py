#!/usr/bin/env python3
"""Deterministic synthetic examples from TZ-01a and SPEC; no personal corpus."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
TABLES={p.stem:json.loads(p.read_text()) for p in (ROOT/'Tests/Fixtures/layouts').glob('*.json')}
PROFILE=dict(enabled=True,pairs=False,roundPairs=False,layoutSwitch=True,reverseLayout=False,correctBeforeEnter=True,retroactive=True,strictLatin=False,spaceOnly=False,inlineCompletion=False,doubleShift=True,backspaceRevert=False,interEventDelayMs=0,chunkSize=20)
CASES=[]
def event(text='',key='character',source='ru',kind='down',time=0,**kw):
 entry=next(iter(sorted([x for x in TABLES.get(source,{}).get('entries',[]) if x['text']==text and not x['dead']],key=lambda x:(x['modifiers'],x['keyCode']))),None)
 e=dict(id=0,time=time,kind=kind,key=key,text=text,keyCode=entry['keyCode'] if entry else None,modifiers=entry['modifiers'] if entry else 0,source=source,own=False,repeatKey=False,secure=False,deadKey=False,caretPosition=None)
 e.update(kw);return e

def typed(text,source='ru',start=0,gap=10,ups=False):
 out=[]
 for c in text:
  key={' ':'space','\n':'enter','\t':'tab'}.get(c,'character')
  out.append(event(c,key,source,time=start));start+=gap
  if ups:out.append(event(c,key,source,kind='up',time=start-gap/2))
 return out

def shifts(start=1000,source='ru',gap=100):
 return [event(key='shift',source=source,kind='flags',time=start,modifiers=1),event(key='shift',source=source,kind='flags',time=start+10),event(key='shift',source=source,kind='flags',time=start+gap,modifiers=1),event(key='shift',source=source,kind='flags',time=start+gap+10)]

def rule(inp='превет',out='привет',source=None,deferred=False,context=None):return dict(input=inp,replacement=out,source=source,deferred=deferred,context=context)

def add(id,events,expected,category='mechanics',**kw):
 profile=PROFILE|kw.pop('profile',{})
 defaults=dict(id=id,category=category,source='ru',field='plain',initialText='',initialCursor=None,selectionLength=0,witnessAvailable=True,witnessLatencyMs=0,boundaryKnown=True,profile=profile,rules=[rule()],decisionDelayMs=0,planStepMs=0,events=events,expectedText=expected,expectedSource=kw.get('source','ru'),expectedCursor=None,requiredActions=[],expectedPlans=None,expectedCancellations=None,completion='completed')
 defaults.update(kw)
 for i,e in enumerate(events):e['id']=i+1
 assert all(a['time']<=b['time'] for a,b in zip(events,events[1:])),id
 CASES.append(defaults)

for i,d in enumerate([' ',',','!','?',':',';',')',']','}','»','…','"','\n']):
 add(f'delimiter-{i:02}',typed('превет'+d),'привет'+d,requiredActions=['trigger','plan'],expectedPlans=1)
add('enter-off',typed('превет\n'),'превет\n',profile={'correctBeforeEnter':False},expectedPlans=0)
add('space-only-comma',typed('превет,'),'превет,',profile={'spaceOnly':True},expectedPlans=0)
add('space-only-space',typed('превет '),'привет ',profile={'spaceOnly':True},expectedPlans=1)
add('enter-completion-off',typed('превет\n'),'преветcompleted',field='enterCompletion',profile={'correctBeforeEnter':False},expectedPlans=0)
add('shift-enter',typed('превет')+[event(key='enter',time=100,modifiers=1)],'привет\n',expectedPlans=1)
add('held-decision',typed('превет abc',gap=3),'привет abc',decisionDelayMs=20,requiredActions=['hold'],expectedPlans=1)
add('held-plan',typed('превет abc',gap=3),'привет abc',planStepMs=5,requiredActions=['hold'],expectedPlans=1)
add('held-keyup-flags',typed('превет ',gap=3,ups=True)+[event(kind='flags',time=21,modifiers=1),event('а',time=22),event(kind='up',time=23)],'привет а',decisionDelayMs=20,requiredActions=['hold'],expectedPlans=1)
add('decision-timeout-25',typed('превет '),'превет ',decisionDelayMs=25,requiredActions=['cancel'],expectedCancellations=1,expectedPlans=0)
add('decision-under-deadline',typed('превет '),'привет ',decisionDelayMs=24.9,expectedPlans=1)
add('queue-overflow',typed('превет ')+[event(kind='flags',time=61+i*.1) for i in range(65)],'превет ',decisionDelayMs=24,requiredActions=['cancel'],expectedPlans=0)
add('queue-at-capacity',typed('превет ')+[event(kind='flags',time=61+i*.1) for i in range(64)],'привет ',decisionDelayMs=24,expectedPlans=1)
add('plan-overflow-completes',typed('превет ')+[event(kind='flags',time=61+i) for i in range(180)],'привет ',planStepMs=30,expectedPlans=1,requiredActions=['hold'])
add('pending-tap-disabled',typed('превет ')+[event(kind='tapDisabled',time=62),event('а',time=64)],'превет а',decisionDelayMs=20,expectedPlans=0,requiredActions=['cancel'])
add('plan-focus-completes',typed('превет ')+[event(kind='focus',time=62)],'привет ',planStepMs=5,expectedPlans=1)
add('undo-in-window',typed('превет ')+[event('z',modifiers=4,time=100)],'превет ',requiredActions=['revert'],expectedPlans=2)
add('undo-after-timeout',typed('превет ')+[event('z',modifiers=4,time=16061)],'привет',expectedPlans=1,requiredActions=['reset'])
add('undo-after-new-input',typed('превет а')+[event('z',modifiers=4,time=100)],'привет ',expectedPlans=1,requiredActions=['reset'])
add('backspace-revert-on',typed('превет ')+[event(key='backspace',time=100)],'превет',profile={'backspaceRevert':True},requiredActions=['revert'],expectedPlans=2)
add('backspace-revert-off',typed('превет ')+[event(key='backspace',time=100)],'привет',expectedPlans=1)
add('shift-undo-latest',typed('превет ')+shifts(),'превет ',requiredActions=['revert'],expectedPlans=2)
add('shift-undo-previous',typed('превет мир ')+shifts(),'превет мир ',requiredActions=['revert'],expectedPlans=2)
add('shift-manual-latin',typed('ghbdtn','en')+shifts(source='en'),'привет',source='en',expectedSource='ru',rules=[],requiredActions=['manualFix'],expectedPlans=1)
add('shift-manual-roundtrip',typed('ghbdtn','en')+shifts(source='en')+shifts(2000,source='ru'),'ghbdtn',source='en',expectedSource='en',rules=[],expectedPlans=2)
add('shift-disabled',typed('ghbdtn','en')+shifts(source='en'),'ghbdtn',source='en',profile={'doubleShift':False},rules=[],expectedPlans=0)
add('shift-too-slow',typed('ghbdtn','en')+shifts(source='en',gap=351),'ghbdtn',source='en',rules=[],expectedPlans=0)
add('shift-exact-limit',typed('ghbdtn','en')+shifts(source='en',gap=350),'привет',source='en',expectedSource='ru',rules=[],expectedPlans=1)
add('shift-manual-russian',typed('превет')+shifts(),'привет',expectedPlans=1)
add('shift-manual-with-space',typed('ghbdtn ','en')+shifts(source='en'),'привет ',source='en',expectedSource='ru',rules=[],expectedPlans=1)
for name,e in [('focus',event(kind='focus')),('mouse',event(kind='mouse')),('tab',event(key='tab')),('cmd-l',event('l',modifiers=4)),('cmd-t',event('t',modifiers=4)),('ctrl-a',event('a',modifiers=8)),('globe',event(key='globe')),('function',event(kind='flags',modifiers=16)),('escape',event(key='escape')),('left',event(key='left'))]:
 e['time']=5
 # Empty initial field, so cursor movement has no separate text effect.
 add('reset-'+name,[e]+typed('превет ',start=10),'превет ',category='reset',expectedPlans=0,requiredActions=['reset'])
add('mouse-middle-word',typed('превет')+[event(kind='mouse',time=70,caretPosition=3)]+typed('а ',start=80),'преа вет',category='reset',expectedPlans=0)
add('boundary-recovered', [event(kind='focus')]+typed('слово превет ',start=10),'слово привет ',category='reset',expectedPlans=1)
add('initial-boundary-unknown',typed('превет '),'превет ',boundaryKnown=False,expectedPlans=0)
add('enter-establishes-boundary',typed('\nпревет '),'\nпривет ',boundaryKnown=False,expectedPlans=1)
add('secure-input-on',[event(kind='secureInput',secure=True)]+typed('превет ',start=10),'превет ',expectedPlans=0)
add('secure-input-off',[event(kind='secureInput',secure=True),event(kind='secureInput',time=1,secure=False)]+typed('превет ',start=10),'превет ',expectedPlans=0)
add('ime-disabled',typed('превет ',source='ime'),'превет ',source='ime',expectedPlans=0)
add('dead-key-reset',[event('а',deadKey=True)]+typed('превет ',start=10),'апревет ',expectedPlans=0)
for opener,closer in [('[',']'),('{','}'),('"','"')]:
 name={'[':'bracket','{':'brace','"':'quote'}[opener]
 add('pair-'+name,typed(opener),opener+closer,category='pairs',profile={'pairs':True},expectedCursor=1,expectedPlans=1,requiredActions=['pairInsert'])
 add('pair-after-space-'+name,typed(' '+opener),' '+opener+closer,category='pairs',profile={'pairs':True},expectedCursor=2,expectedPlans=1)
 add('pair-overtype-'+name,typed(opener+closer),opener+closer,category='pairs',profile={'pairs':True},expectedCursor=2,expectedPlans=2,requiredActions=['pairOvertype'])
 add('pair-delete-'+name,typed(opener)+[event(key='backspace',time=50)],'',category='pairs',profile={'pairs':True},expectedCursor=0,expectedPlans=2,requiredActions=['pairDelete'])
add('quote-inside-word',typed('слово"'),'слово"',profile={'pairs':True},rules=[],expectedPlans=0)
add('bracket-inside-word',typed('слово['),'слово[]',profile={'pairs':True},rules=[],expectedCursor=6,expectedPlans=1)
add('brace-inside-word',typed('слово{'),'слово{}',profile={'pairs':True},rules=[],expectedCursor=6,expectedPlans=1)
add('pairs-navigation-forgets',typed('[')+[event(key='left',time=30)]+typed(']',start=40),'][]',profile={'pairs':True},expectedPlans=1)
add('field-autopairs-profile-off',typed('[]'), '[]',field='autoPairs',profile={'pairs':False},expectedPlans=0)
add('correction-before-overtype',typed('[превет]'),'[привет]',profile={'pairs':True},expectedPlans=2)
add('nested-pairs',typed('[{}]'),'[{}]',profile={'pairs':True},expectedPlans=4)
add('round-pairs-disabled',typed('('),'(',profile={'pairs':True},expectedPlans=0)
add('round-pairs-enabled',typed('()'),'()',profile={'pairs':True,'roundPairs':True},expectedPlans=2)
for n,token in [('url','https://пример.рф'),('email','a@example.test'),('mention','@превет'),('hashtag','#превет'),('digits','превет1'),('underscore','превет_'),('mixed','преветa'),('path','/превет'),('backslash','x\\превет'),('code','`превет`'),('acronym','ПРВТ'),('short','да'),('domain','сайт.рф'),('abbreviation','т.е.')]:
 add('excluded-'+n,typed(token+' '),token+' ',category='exceptions',rules=[rule(token,'замена')],expectedPlans=0)
add('capital-inside-sentence',typed('слово Превет '),'слово Превет ',rules=[rule('Превет','Привет')],expectedPlans=0)
add('capital-at-start',typed('Превет '),'Привет ',rules=[rule('Превет','Привет')],expectedPlans=1)
add('soft-period-space',typed('превет. '),'привет. ',requiredActions=['softTrigger'],expectedPlans=1)
add('soft-period-enter',typed('превет.\n'),'привет.\n',expectedPlans=1)
add('soft-period-letter',typed('превет.рф '),'превет.рф ',expectedPlans=0)
add('soft-period-digit',typed('превет.1 '),'превет.1 ',expectedPlans=0)
add('soft-period-no-followup',typed('превет.'),'превет.',expectedPlans=0)
for n,inp,out in [('plain','ghbdtn','привет'),('title','Ghbdtn','Привет'),('bracket','[jhjij','хорошо'),('quote','"nj','Это'),('comma-tail','ghbdtn?','привет,'),('period-tail','ghbdtn/','привет.')]:
 add('layout-'+n,typed(inp+' ','en'),out+' ',category='layout',source='en',expectedSource='ru-pc' if n in ['comma-tail','period-tail'] else 'ru',profile={'pairs':True},rules=[rule(inp,source='ru-pc' if n in ['comma-tail','period-tail'] else 'ru')],requiredActions=['trigger'],expectedPlans=2 if n in ['bracket','quote'] else 1)
add('layout-deferred-short',typed('yt ','en'),'yt ',source='en',rules=[rule('yt',source='ru',deferred=True)],expectedPlans=0)
for inp,out in [('yt pyf','не зна'),('yt pyf.','не знаю')]:
 add('layout-two-words-'+('complete' if inp.endswith('.') else 'literal'),typed(inp+' ','en'),out+' ',source='en',expectedSource='ru',rules=[rule('yt',source='ru',deferred=True),rule(inp,source='ru')],expectedPlans=1)
add('layout-undo-source',typed('ghbdtn ','en')+[event('z',modifiers=4,time=100,source='ru')],'ghbdtn ',source='en',rules=[rule('ghbdtn',source='ru')],expectedPlans=2)
add('layout-held-rebased',typed('ghbdtn f','en',gap=3),'привет а',source='en',expectedSource='ru',rules=[rule('ghbdtn',source='ru')],decisionDelayMs=20,requiredActions=['hold'],expectedPlans=1)
add('layout-disabled',typed('ghbdtn ','en'),'ghbdtn ',source='en',rules=[rule('ghbdtn',source='ru')],profile={'layoutSwitch':False},expectedPlans=0)
add('layout-camelcase',typed('iPhone ','en'),'iPhone ',source='en',rules=[rule('iPhone',source='ru')],expectedPlans=0)
for name,mod in [('command',4),('option',2),('shift',1)]:
 add('modifier-during-plan-'+name,typed('превет ')+[event(kind='flags',time=61,modifiers=mod)],'привет ',planStepMs=4,expectedPlans=1,requiredActions=['hold'])
add('selection-reject',typed('превет '),'превет ',initialText='hint',initialCursor=0,selectionLength=4,field='inlineCompletion',profile={'inlineCompletion':True},expectedPlans=0,expectedCancellations=1)
# Selection remains after an externally supplied prefix; typing just a delimiter must not replace the hint.
add('inline-no-witness',typed('превет '),'превет ',field='inlineCompletion',witnessAvailable=False,profile={'inlineCompletion':True},expectedPlans=0,expectedCancellations=1)
add('inline-slow-witness',typed('превет '),'превет ',field='inlineCompletion',witnessLatencyMs=21,profile={'inlineCompletion':True},expectedPlans=0,expectedCancellations=1)
add('ordinary-no-witness',typed('превет '),'привет ',witnessAvailable=False,expectedPlans=1)
add('substitution-mismatch',typed('превет '),'Превет ',field='substitutions',expectedPlans=0,expectedCancellations=1)
add('slow-backspace-safe-profile',typed('превет '),'привет ',field='slowBackspace',profile={'interEventDelayMs':3},expectedPlans=1)
add('key-repeat',typed('ааа')+[event('а',time=40,repeatKey=True)],'аааа',rules=[],expectedPlans=0)
add('buffer-overflow-no-boundary',typed('а'*405+'превет '),'а'*405+'превет ',expectedPlans=0)
add('profile-disabled',typed('превет '),'превет ',profile={'enabled':False},expectedPlans=0)
for key in ['c','s','f']:
 add('whitelist-'+key,typed('пре')+[event(key,modifiers=4,time=40)]+typed('вет ',start=50),'привет ',expectedPlans=1)
add('layout-short-forced-defer',typed('yt ','en'),'yt ',source='en',rules=[rule('yt',source='ru')],expectedPlans=0)
add('enter-correction-undo',typed('превет\n')+[event('z',modifiers=4,time=200)],'превет\n',expectedPlans=2)
add('layout-reverse-on',typed('руддщ '),'hello ',expectedSource='en',profile={'reverseLayout':True},rules=[rule('руддщ',source='en')],expectedPlans=1)
add('layout-reverse-off',typed('руддщ '),'руддщ ',rules=[rule('руддщ',source='en')],expectedPlans=0)
add('pair-conversion-undo-overtype',typed('[jhjij ','en')+[event('z',modifiers=4,time=100,source='ru'),event(']',time=150,source='en')],'[jhjij ]',source='en',rules=[rule('[jhjij',source='ru')],profile={'pairs':True},expectedPlans=4)
add('user-source-change-during-plan',typed('ghbdtn ','en')+[event(kind='sourceChanged',source='en',time=62),event('f',source='en',time=63)],'привет f',source='en',rules=[rule('ghbdtn',source='ru')],planStepMs=5,expectedPlans=1)
add('queued-shift-preserves-time',typed('превет ')+shifts(start=100,gap=351),'привет ',planStepMs=100,expectedPlans=1)
add('backspace-joins-tokens',typed('слово ')+[event(key='backspace',time=80)]+typed('превет ',start=90),'словопревет ',expectedPlans=0)
add('backspace-restores-unknown-boundary',typed('превет ')+[event(key='backspace',time=80),event(key='space',time=90)],'превет ',boundaryKnown=False,expectedPlans=0)
add('consecutive-comma-corrections',typed('превет,превет '),'привет,привет ',expectedPlans=2)
add('open-bracket-boundary-pairs-off',typed('[превет '),'[привет ',profile={'pairs':False},expectedPlans=1)
add('undo-delimiter-keeps-original',typed('превет,')+[event('z',modifiers=4,time=100),event(key='backspace',time=110),event(key='space',time=120)],'превет ',expectedPlans=2)
(ROOT/'Tests/Scenarios/mechanics.yaml').write_text(json.dumps(CASES,ensure_ascii=False,indent=2)+'\n')
print('scenarios',len(CASES))
