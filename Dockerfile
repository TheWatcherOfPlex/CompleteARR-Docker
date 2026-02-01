FROM mcr.microsoft.com/powershell:7.4-ubuntu-22.04

WORKDIR /app

RUN apt-get update \
    && apt-get install -y curl ca-certificates gnupg \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN pwsh -Command "Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; Install-Module powershell-yaml -Force -Scope AllUsers"

COPY . /app

RUN npm --prefix /app/ui install

# Keep npm updated so build output stays clean and current.
RUN npm install -g npm@11.8.0
RUN chmod +x /app/docker/entrypoint.sh

EXPOSE 3005

ENTRYPOINT ["bash", "/app/docker/entrypoint.sh"]