FROM photon:3.0
LABEL version="1.0" description="PXE boot with dchp, tftp and http services"
EXPOSE 67/udp 67/tcp 69/udp 8000/tcp
COPY ["endpoint.sh", "/opt/"]
RUN /bin/bash "/opt/endpoint.sh"
ENTRYPOINT ["/opt/endpoint.sh", "SERVICE"]