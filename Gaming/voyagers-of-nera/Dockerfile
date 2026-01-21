# Start from optimized SteamCMD base and add Wine
FROM cm2network/steamcmd:root

LABEL maintainer="Voyagers of Nera Docker"
LABEL description="Voyagers of Nera Dedicated Server (Wine)"

ENV DEBIAN_FRONTEND=noninteractive

# Server configuration
ENV SERVER_PORT=7777
ENV EOS_OVERRIDE_HOST_IP=""
ENV ENABLE_LOGGING=true
ENV QUERY_PORT=""
ENV ONLINE_SUBSYSTEM=""

# Host Server Settings
ENV HOST_SERVER_DISPLAY_NAME="flux"
ENV HOST_SERVER_PASSWORD=""
ENV MAX_PLAYERS=10
ENV AUTOSAVE_TIMER_SECONDS=300

# Game Settings
ENV GATHERING_RATE_MULTIPLIER=1.0
ENV ENEMY_DAMAGE_MULTIPLIER=1.0
ENV PLAYER_DAMAGE_MULTIPLIER=1.0
ENV DISABLE_EQUIPMENT_DURABILITY=False
ENV DISABLE_DROP_ITEMS_ON_DEATH=False

# Config defaults (match official workflow: run once, edit configs)
ENV MANAGE_CONFIG=true
ENV CLEAR_ENGINE_INI=false
ENV CLEAR_CUSTOM_CONFIGS=false
ENV USE_STUB_EXE=false

# Wine defaults
ENV WINEPREFIX=/home/steam/.wine
ENV WINEARCH=win64
ENV WINEDEBUG=-all
ENV DISPLAY=:99
ENV HOME=/home/steam
ENV USER=steam

# Install dependencies and Wine
RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        xvfb \
        gosu \
        ca-certificates \
        wget \
        gnupg2 \
        cabextract \
        unzip \
        p7zip-full \
    && mkdir -pm755 /etc/apt/keyrings \
    && wget -q -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key \
    && wget -q -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/debian/dists/bookworm/winehq-bookworm.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends winehq-stable \
    && wget -q https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks -O /usr/local/bin/winetricks \
    && chmod +x /usr/local/bin/winetricks \
    && apt-get clean \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/locale/*

# Setup directories
RUN mkdir -p /home/steam/nera/server /home/steam/.wine \
    && chown -R steam:steam /home/steam

COPY --chmod=755 entrypoint.sh /entrypoint.sh

WORKDIR /home/steam/nera/server

EXPOSE 7777/udp 7778/udp 27015/udp

ENTRYPOINT ["/entrypoint.sh"]
