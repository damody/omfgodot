-- The formal MOBA launch with the Godot renderer: authority, client runtime, then Godot.
-- Options are moba_role_launch's, plus --godot EXE, --finish-timeout SECONDS and --result-png FILE.
local source=debug.getinfo(1,'S').source:sub(2)
-- This file sits in omoba/omfgodot/scripts; the launch libraries live in omoba/scripts.
local here=assert(source:match('^(.*)[/\\]'))
package.path=here..'/../../scripts/?.lua;'..here..'/?.lua;'..package.path
local b=require('_bootstrap')
local path,process,time,platform=b.lib('path'),b.lib('process'),b.lib('time'),b.lib('platform')
local launch=require('moba_role_launch')
local artifacts=require('run_artifacts')

local godot=os.getenv('GODOT4') or path.join(b.root,'..','tools','godot','Godot_v4.7.2-stable_win64.exe')
local finish_timeout,result_png,input_smoke,focus
local forwarded={}
do
  local i=1
  while i<=#arg do
    if arg[i]=='--godot' then godot=arg[i+1];i=i+2
    elseif arg[i]=='--finish-timeout' then finish_timeout=assert(math.tointeger(tonumber(arg[i+1])),'--finish-timeout takes seconds');i=i+2
    elseif arg[i]=='--result-png' then result_png=path.absolute(arg[i+1],b.root);i=i+2
    elseif arg[i]=='--input-smoke' then input_smoke=true;i=i+1
    elseif arg[i]=='--focus' then focus=arg[i+1];i=i+2
    else forwarded[#forwarded+1]=arg[i];i=i+1 end
  end
end
local options=launch.options(forwarded)
assert(path.is_file(godot),'missing Godot executable: '..godot..' (set GODOT4 or pass --godot)')
process.supervise_workflow(source,arg)

local function run(exe,args,label)
  local result=process.run(exe,args,{cwd=b.root,check=false})
  assert(result.exit_code==0,label..' failed: '..tostring(result.stderr):sub(-4000))
end
if not options.no_build then
  local lock=require('build_lock').acquire(b.root,'run_moba_role_gd build phase')
  local release=options.profile=='release' and {'--release'} or {}
  local function cargo(...)
    local args={'build',...}
    for _,flag in ipairs(release) do args[#args+1]=flag end
    run('cargo',args,'cargo '..table.concat(args,' '))
  end
  local scripts=require('moba_server_build').script_dll_command(options.profile)
  run(scripts.exe,scripts.args,'script DLLs')
  cargo('--manifest-path',path.join(b.root,'omb','Cargo.toml'),'-p','omobab','--bin','moba-config','--features','compiled-content-only')
  cargo('--manifest-path',path.join(b.root,'omb','Cargo.toml'),'-p','omobab','--bin','omobab','--features','compiled-content-only')
  cargo('--manifest-path',path.join(b.root,'omoba-client-runtime','Cargo.toml'),'--features','compiled-content-only')
  cargo('--manifest-path',path.join(b.root,'omfgodot','omgd','om_godot','Cargo.toml'))
  lock:release()
end

local dll=path.join(b.root,'omfgodot','omgd','game','bin','om_godot.dll')
local built=path.join(b.root,'omfgodot','omgd','om_godot','target',options.profile,'om_godot.dll')
if path.is_file(built) then path.write(dll,path.read(built,true),true,true) end

-- Registers class_name scripts and imports art; a project that was never imported fails to parse.
run(godot,{'--headless','--path',path.join(b.root,'omfgodot','omgd','game'),'--import'},'Godot import')

if not options.output then
  local lfs=require('lfs')
  local parent=path.mkdir_p(path.join(b.root,'target','role-gd-runs'))
  for suffix=1,1000 do
    local reserved=path.join(parent,os.time()..'-'..suffix)
    if lfs.mkdir(reserved) then options.output=path.join(reserved,'session');break end
  end
  assert(options.output,'cannot reserve run directory')
end
local plan=launch.prepare(options,process)
-- The bridge inside om_godot.dll refuses a runtime with other content, and no frame would ever show.
artifacts.verify_content({{role='renderer bridge',file=dll}},plan.content_hash)
print(('Prepared %d human(s), %d Bot(s), map %s: %s'):format(plan.human_count,plan.bot_count,plan.map_id,plan.output))

local lock <close> = require('machine_lock').acquire(b.root,'live_match',{run=plan.output,
  label='run_moba_role_gd',wait_seconds=options.wait_live_lock or 0})
local function spawn(label,spec)
  assert(path.is_file(spec.exe),'missing executable: '..spec.exe)
  local stdout,stderr=path.join(plan.output,label..'.stdout.log'),path.join(plan.output,label..'.stderr.log')
  local pid,record=process.spawn_owned(spec.exe,spec.args,{cwd=spec.cwd,env=spec.env,stdout=stdout,stderr=stderr})
  record=process.validate_owned(record)
  lock:attach(record,label)
  return record,stdout,stderr
end

local server,server_out,server_err=spawn('server',plan.server)
launch.wait_server_bound(server,server_out,server_err,process,time)
-- The listener opens while the script DLLs are still loading, and a client that joins before the
-- last one is refused with SCRIPT_MODULES_HASH_MISMATCH.
do
  local expected=#plan.base_content.script_modules
  local deadline=time.monotonic_ms()+60000
  while true do
    local _,loaded=path.read(server_out):gsub('%[scripting%] loaded ','')
    if loaded>=expected then break end
    assert(process.owned_alive(server),'server exited while loading scripts; see '..server_out)
    assert(time.monotonic_ms()<deadline,('server loaded %d of %d script DLLs in 60 s; see %s'):format(loaded,expected,server_out))
    time.sleep_ms(100)
  end
end
local renderers={}
for _,client in ipairs(plan.clients) do
  local runtime,out,errors=spawn('runtime-p'..client.player_id,client.runtime)
  process.poll_owned_ready(runtime,45000,function()
    assert(process.owned_alive(server),'server exited before runtime ready')
    return launch.runtime_ready((path.is_file(out) and path.read(out) or '')..(path.is_file(errors) and path.read(errors) or ''),client)
  end,'runtime-p'..client.player_id)
  local args={'--path',path.join(b.root,'omfgodot','omgd','game'),'--resolution','1280x720','--',
    '--om-presentation='..client.presentation,'--om-player='..client.player_id,'--om-team='..client.team_id,
    '--om-map='..plan.map_id}
  if finish_timeout then args[#args+1]='--om-finish-timeout='..finish_timeout end
  if result_png then args[#args+1]='--om-result='..result_png end
  if input_smoke then args[#args+1]='--om-input-smoke' end
  if focus then args[#args+1]='--om-focus='..focus end
  renderers[#renderers+1]=spawn('godot-p'..client.player_id,{exe=godot,args=args,cwd=path.join(b.root,'omfgodot','omgd','game'),env={}})
end
print('Humans admitted; Godot started. Logs: '..plan.output)
while true do
  local active=false
  for _,record in ipairs(renderers) do active=process.owned_alive(record) or active end
  if not active then break end
  time.sleep_ms(500)
end
if process.owned_alive(server) then process.stop_owned(server) end
print('Godot closed; run retired: '..plan.output)
