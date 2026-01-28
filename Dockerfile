FROM mcr.microsoft.com/powershell:7.4-ubuntu-22.04

WORKDIR /app

RUN pwsh -Command "Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; Install-Module powershell-yaml -Force -Scope AllUsers"

COPY . /app

RUN chmod +x /app/docker/entrypoint.sh

ENTRYPOINT ["bash", "/app/docker/entrypoint.sh"]