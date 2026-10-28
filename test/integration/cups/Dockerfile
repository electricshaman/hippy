# Throwaway CUPS server for Hippy integration tests. See test/integration/cups_test.exs.
FROM debian:bookworm-slim
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      cups cups-client cups-bsd cups-filters cups-ipp-utils && rm -rf /var/lib/apt/lists/*
RUN useradd -M hippy && echo 'hippy:hippy-pass' | chpasswd
COPY cupsd.conf /etc/cups/cupsd.conf
COPY start.sh /start.sh
RUN echo 'FileDevice Yes' >> /etc/cups/cups-files.conf && chmod +x /start.sh
EXPOSE 631
CMD ["/start.sh"]
