# escape=`
# Microsoft MCR manifest and MinGit release digest verified 2026-11-08.
FROM mcr.microsoft.com/windows/servercore:ltsc2022@sha256:b52799a67fa596d4bddcd82ae1dab0077a84767fbc33c7342b72b53ecc71ad09 AS devel
SHELL ["powershell.exe", "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"]
COPY script/docker/install_min_git.ps1 C:/tools/install_min_git.ps1
RUN C:/tools/install_min_git.ps1
COPY script/docker/install_python.ps1 C:/tools/install_python.ps1
RUN C:/tools/install_python.ps1
ENV PATH="C:\git\cmd;C:\python;${PATH}" GIT_OPTIONAL_LOCKS="0"
RUN git.exe --version; if ($LASTEXITCODE -ne 0) { throw 'Git unavailable' }
USER ContainerUser
WORKDIR C:/workspace
CMD ["powershell.exe", "-NoLogo", "-NoProfile"]

FROM devel AS test
COPY script/docker/container_test.ps1 C:/tools/container_test.ps1
CMD ["powershell.exe", "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "C:/tools/container_test.ps1"]
