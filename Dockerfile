#
# "chatarrero" base by Luispa, Dec 2014
# 
# Chatarrero = amavisd-new + clamAV + Spamassassin
#
# -----------------------------------------------------

#
# Desde donde parto...
#
FROM debian:jessie

# Autor de este Dockerfile
#
MAINTAINER Luis Palacios <luis@luispa.com>

# Pido que el frontend de Debian no sea interactivo
ENV DEBIAN_FRONTEND noninteractive

# Actualizo el sistema operativo e instalo lo mínimo
#
RUN apt-get update && \
    apt-get -y install 	locales \
    					net-tools \
                       	vim \
                       	supervisor \
                       	wget \
                       	curl \
                        rsyslog

# Preparo locales y Timezone
#
RUN locale-gen es_ES.UTF-8
RUN locale-gen en_US.UTF-8
RUN dpkg-reconfigure locales
RUN echo "Europe/Madrid" > /etc/timezone; dpkg-reconfigure -f noninteractive tzdata

# HOME
ENV HOME /root

# ------- ------- ------- ------- ------- ------- -------
# Instalo amavisd-new, clamav, spamassassin
# ------- ------- ------- ------- ------- ------- -------
#
# Instalo los paquetes básicos
#
RUN apt-get update && \
    apt-get -y install amavisd-new \
    				   spamassassin \
    				   clamav-daemon 

# Instalo paquetes adicionales para mejorar la detección del spam
#
RUN apt-get update && \
    apt-get -y install 	libencode-detect-perl \
    				   	libdbi-perl \
    				   	libdbd-mysql-perl \
    					libnet-dns-perl \
    					libmail-spf-perl \
    					pyzor \
    					razor
    					
# Instalo paquetes para poder descomprimir anexos y mejorar el scanning de ficheros
#
RUN apt-get update && \
    apt-get -y install 	arj \
    					bzip2 \
    					cabextract \
    					cpio \
    					file \
    					gzip \
    					nomarch \
    					pax \
    					unp \
    					unrar-free \
    					unzip \
    					zip \
    					lzop \
    					p7zip-full \
    					rpm2cpio \
    					zoo

# Ambos, ClamAV y Amavisd-new, en el grupo del otro
#
RUN adduser clamav amavis
RUN adduser amavis clamav

# Instalo dcc
#
WORKDIR /root
RUN wget http://www.dcc-servers.net/src/dcc/dcc-dccd.tar.Z
RUN tar xzf dcc-dccd.tar.Z  && cd dcc* && ./configure --with-uid=amavis && make && make install

# Puerto por el que escucha amavisd-new
#
EXPOSE 10024

# ------- ------- ------- ------- ------- ------- -------
# DEBUG ( Descomentar durante debug del contenedor )
# ------- ------- ------- ------- ------- ------- -------
#
# Herramientas SSH, tcpdump y net-tools
#RUN apt-get update && \
#    apt-get -y install 	openssh-server \
#                       	tcpdump \
#                        net-tools
## Setup de SSHD
#RUN mkdir /var/run/sshd
#RUN echo 'root:docker' | chpasswd
#RUN sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' /etc/ssh/sshd_config
#RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd
#ENV NOTVISIBLE "in users profile"
#RUN echo "export VISIBLE=now" >> /etc/profile

## Script que uso a menudo durante las pruebas. Es como "cat" pero elimina líneas de comentarios
RUN echo "grep -vh '^[[:space:]]*#' \"\$@\" | grep -v '^//' | grep -v '^;' | grep -v '^\$' | grep -v '^\!' | grep -v '^--'" > /usr/bin/confcat
RUN chmod 755 /usr/bin/confcat

#-----------------------------------------------------------------------------------

# Ejecutar siempre al arrancar el contenedor este script
#
ADD do.sh /do.sh
RUN chmod +x /do.sh
ENTRYPOINT ["/do.sh"]

#
# Si no se especifica nada se ejecutará lo siguiente: 
#
CMD ["/usr/bin/supervisord", "-n -c /etc/supervisor/supervisord.conf"]
