import json,subprocess,sys,os,wave
SP=sys.argv[1]
lines=json.load(open(f"{SP}/work/script.json"))
model=f"{SP}/tts/en_US-amy-medium.onnx"
tot=0
out={}
for L in lines:
    p=f"{SP}/vo/{L['id']}.wav"
    subprocess.run(["python3","-I","-m","piper","-m",model,"-f",p,
                    "--length-scale","1.06","--sentence-silence","0.32"],
                   input=L["say"],text=True,check=True,
                   stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    with wave.open(p) as w: d=w.getnframes()/w.getframerate()
    out[L["id"]]=round(d,2); tot+=d
    print(f"{L['id']} sec{L['sec']} {d:5.2f}s  {L['say'][:58]}")
json.dump(out,open(f"{SP}/work/vo_durations.json","w"),indent=1)
print(f"\nTOTAL narration audio: {tot:.1f}s  ({tot/60:.2f} min)")
for s in (1,2,3,4):
    print(f"  section {s}: {sum(out[L['id']] for L in lines if L['sec']==s):.1f}s")
