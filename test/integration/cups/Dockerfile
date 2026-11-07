# Throwaway CUPS server for Hippy integration tests. See test/integration/cups_test.exs.
FROM debian:bookworm-slim
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      cups cups-client cups-bsd cups-filters cups-ipp-utils avahi-daemon dbus && rm -rf /var/lib/apt/lists/*
RUN useradd -M hippy && echo 'hippy:hippy-pass' | chpasswd
# An administrator: CUPS's SystemGroup includes lpadmin.
RUN useradd -M -G lpadmin hippy-admin && echo 'hippy-admin:admin-pass' | chpasswd
COPY cupsd.conf /etc/cups/cupsd.conf
COPY start.sh /start.sh
RUN echo 'FileDevice Yes' >> /etc/cups/cups-files.conf && chmod +x /start.sh
# 631: CUPS. 8631: ippeveprinter, standing in for a driverless printer at home.
EXPOSE 631 8631
CMD ["/start.sh"]
