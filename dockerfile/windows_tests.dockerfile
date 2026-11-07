# escape=`
# Microsoft MCR manifest and MinGit release digest verified 2026-11-08.
FROM mcr.microsoft.com/windows/servercore:ltsc2022@sha256:b52799a67fa596d4bddcd82ae1dab0077a84767fbc33c7342b72b53ecc71ad09 AS devel
SHELL ["C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe", "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"]
COPY script/docker/install_min_git.ps1 C:/tools/install_min_git.ps1
RUN C:/tools/install_min_git.ps1
COPY script/docker/install_python.ps1 C:/tools/install_python.ps1
RUN C:/tools/install_python.ps1
# The pinned Windows image has case-sensitive Docker metadata but Windows treats
# Path case-insensitively. Do not expand ${PATH}: it can erase system tools.
ENV PATH="C:\git\cmd;C:\python;C:\Windows\System32;C:\Windows;C:\Windows\System32\Wbem;C:\Windows\System32\WindowsPowerShell\v1.0" GIT_OPTIONAL_LOCKS="0"
RUN $ErrorActionPreference='Stop'; foreach ($tool in @('powershell.exe','cmd.exe','git.exe','python.exe')) { Get-Command $tool -CommandType Application -ErrorAction Stop | Out-Null }; git.exe --version; if ($LASTEXITCODE -ne 0) { throw 'Git unavailable' }; python.exe --version; if ($LASTEXITCODE -ne 0) { throw 'Python unavailable' }
USER ContainerUser
WORKDIR C:/workspace
CMD ["C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe", "-NoLogo", "-NoProfile"]

FROM devel AS test
COPY script/docker/container_test.ps1 C:/tools/container_test.ps1
CMD ["C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe", "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "C:/tools/container_test.ps1"]
