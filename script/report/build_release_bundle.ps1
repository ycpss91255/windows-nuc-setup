#Requires -Version 5.1
$ErrorActionPreference='Stop'
$tool=Join-Path $env:RUNNER_TEMP 'report_bundle_tool.exe'
& go.exe build -o $tool ./script/test/report_bundle_tool
if($LASTEXITCODE -ne 0){throw '報表工具建置失敗。'}
$archive=Join-Path $env:RUNNER_TEMP ('windows_setup_report_'+$env:GITHUB_REF_NAME+'.zip')
$native=Join-Path $env:RUNNER_TEMP ('windows-test-reports-'+$env:GITHUB_RUN_ID+'-'+$env:GITHUB_RUN_ATTEMPT)
$container=Join-Path $env:RUNNER_TEMP ('docker-test-reports-'+$env:GITHUB_RUN_ID+'-'+$env:GITHUB_RUN_ATTEMPT)
$identity=@('--source-root',$PWD.Path,'--version',$env:GITHUB_REF_NAME,'--commit',$env:GITHUB_SHA,'--run-url',('https://github.com/'+$env:GITHUB_REPOSITORY+'/actions/runs/'+$env:GITHUB_RUN_ID),'--run-attempt',$env:GITHUB_RUN_ATTEMPT)
& $tool export --native-dir $native --container-dir $container @identity --output $archive
if($LASTEXITCODE -ne 0){throw '報表封裝失敗。'}
& $tool verify --archive $archive @identity
if($LASTEXITCODE -ne 0){throw '報表驗證失敗。'}
