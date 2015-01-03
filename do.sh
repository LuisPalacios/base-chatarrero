#!/bin/bash
#
# Punto de entrada para el servicio chatarrero: amavisd-new, clamav, spamassassin
#
# Activar el debug de este script:
# set -eux

##################################################################
#
# main
#
##################################################################

# Averiguar si necesito configurar por primera vez
#
CONFIG_DONE="/.config_chatarrero_done"
NECESITA_PRIMER_CONFIG="si"
if [ -f ${CONFIG_DONE} ] ; then
    NECESITA_PRIMER_CONFIG="no"
fi

##################################################################
#
# VARIABLES OBLIGATORIAS
#
##################################################################

## Servidor:Puerto por el que conectar con el servidor MYSQL
#
if [ -z "${MYSQL_LINK}" ]; then
	echo >&2 "error: falta el Servidor:Puerto del servidor MYSQL: MYSQL_LINK"
	exit 1
fi
mysqlHost=${MYSQL_LINK%%:*}
mysqlPort=${MYSQL_LINK##*:}

## Mi nombre de host
#
if [ -z "${MYHOSTNAME}" ]; then
	echo >&2 "error: falta la variable MYHOSTNAME"
	exit 1
fi

## Variables para acceder al servidor POSTFIX tras limpiar la chatarra
#
if [ -z "${POSTFIX_LINK}" ]; then
	echo >&2 "error: falta la variable POSTFIX_LINK"
	exit 1
fi

## Variables para decidir: 
#
#  VIRUS_ADMIN   : Destinatario de aviso de virus
#  QUARANTINE_TO : Destinatario de mails que se ponen en cuarentena
#  HAM_TO        : Cuenta con correo BUENO para sa-learn
#
if [ -z "${VIRUS_ADMIN}" ]; then
	echo >&2 "error: falta la variable VIRUS_ADMIN"
	exit 1
fi
if [ -z "${QUARANTINE_TO}" ]; then
	echo >&2 "error: falta la variable QUARANTINE_TO"
	exit 1
fi
if [ -z "${HAM_TO}" ]; then
	echo >&2 "error: falta la variable HAM_TO"
	exit 1
fi

## Variables para acceder a la BD de PostfixAdmin donde están
#  todos los usuarios, contraseñas, dominios, etc...
#
if [ -z "${MAIL_DB_USER}" ]; then
	echo >&2 "error: falta la variable MAIL_DB_USER"
	exit 1
fi
if [ -z "${MAIL_DB_PASS}" ]; then
	echo >&2 "error: falta la variable MAIL_DB_PASS"
	exit 1
fi
if [ -z "${MAIL_DB_NAME}" ]; then
	echo >&2 "error: falta la variable MAIL_DB_NAME"
	exit 1
fi

## Servidor:Puerto por el que escucha el agregador de Logs (fluentd)
#
if [ -z "${FLUENTD_LINK}" ]; then
	echo >&2 "error: falta el Servidor:Puerto por el que escucha fluentd, variable: FLUENTD_LINK"
	exit 1
fi
fluentdHost=${FLUENTD_LINK%%:*}
fluentdPort=${FLUENTD_LINK##*:}

##################################################################
#
# PREPARAR EL CONTAINER POR PRIMERA VEZ
#
##################################################################

# Necesito configurar por primera vez?
#
if [ ${NECESITA_PRIMER_CONFIG} = "si" ] ; then
	
	echo "Realizo la configuración por primera vez"
	
	############
	#
	# amavisd-new  
	#
	############
	echo "Configuro ficheros amavisd-new"

	#
	# amavisd-new escucha por el puerto 10024 por defecto, no hace falta cambiarlo
	#
	# 
	# Parámetros principales
	#
	#   $inet_socket_port = 10024;     # viene por defecto
	#   $inet_socket_bind = '0.0.0.0'; # lo añado en el 50-user (más abajo)
    
	# Activo el filtrado antivirus y spamassassin
	#
    cat > /etc/amavis/conf.d/15-content_filter_mode <<EOFCONTENT
use strict;
@bypass_virus_checks_maps = (
   \%bypass_virus_checks, \@bypass_virus_checks_acl, \\\$bypass_virus_checks_re);
@bypass_spam_checks_maps = (
   \%bypass_spam_checks, \@bypass_spam_checks_acl, \\\$bypass_spam_checks_re);
1;
EOFCONTENT
	
	cat > /etc/amavis/conf.d/50-user <<EOFUSER
use strict;

# Escuchar todas las interfaces. Soy un contenedor independiente de postfix
\$inet_socket_bind = '0.0.0.0';

# Tras el scan, enviarselo a Postfix al puerto 10025
\$forward_method = 'smtp:${POSTFIX_LINK}';
\$notify_method = \$forward_method;

# A que cuenta enviarle los mails por alertas de virus
\$virus_admin = "${VIRUS_ADMIN}";

# Donde enviar los detectados como virus, banned, bad_header y quarantine
\$virus_quarantine_to      = '';    # Los virus los tiro, no los guardo
\$banned_quarantine_to     = 'banned-quarantine';     # local quarantine
\$bad_header_quarantine_to = 'bad-header-quarantine'; # local quarantine
\$spam_quarantine_to       = '${QUARANTINE_TO}';       # local quarantine

# Poner siempre cabeceras spam
#\$sa_tag_level_deflt  = -100;
\$sa_tag_level_deflt  = -9999;

# Poner cabecera detectado spam, tambien conocido como X-Spam-Status
# a partir del siguiente nivel (notar que es muy agresivo).
\$sa_tag2_level_deflt = 5.0;

# Desencadenar acciones avasivas al siguiente nivel de spam, en mi 
# caso todo lo detectado como spam se condena a ser "evadido" :)
\$sa_kill_level_deflt = \$sa_tag2_level_deflt;

# No enviar notificaciones de entrega al emisor a partir de este nivel de spam
\$sa_dsn_cutoff_level = 8;

# No devolverver mensajes a diestro y siniestro, mejor ponerlos en cuarentena
\$final_virus_destiny      = D_DISCARD;  # (defaults to D_DISCARD)
\$final_banned_destiny     = D_DISCARD;  # (defaults to D_BOUNCE)
\$final_spam_destiny       = D_DISCARD;  # (defaults to D_BOUNCE)

# 
@lookup_sql_dsn = (
    ['DBI:mysql:database=${MAIL_DB_NAME};host=${mysqlHost};port=${mysqlPort}',
    '${MAIL_DB_USER}',
    '${MAIL_DB_PASS}']);
\$sql_select_policy = 'SELECT domain from domain WHERE CONCAT("@",domain) IN (%k)';

#
\$log_level = 1;

1;  # ensure a defined return
EOFUSER

	cat > /etc/amavis/conf.d/05-node_id <<EOFNODE
use strict;
\$myhostname = "${MYHOSTNAME}";

1;  # ensure a defined return
EOFNODE

	cat > /etc/amavis/conf.d/25-amavis_helpers <<EOFHELPERS	
use strict;

\$unix_socketname = "/var/lib/amavis/amavisd.sock";

\$interface_policy{'SOCK'} = 'AM.PDP-SOCK';
\$policy_bank{'AM.PDP-SOCK'} = {
  protocol => 'AM.PDP',
  auth_required_release => 0, # don't require secret-id for release
};

\$interface_policy{'10024'} = 'EXT';
\$policy_bank{'EXT'} = {

  inet_acl => [qw( 127.0.0.1 172.16.0.0/12 [::1] )], # Solo acepto desde IP's de docker
  auth_required_release => 0,  # don't require secret_id for amavisd-release
  
};

1;  # ensure a defined return
EOFHELPERS

	############
	#
	# clamd.conf
	#
	############
	echo "Configuro clamd.conf"

	chown clamav:clamav /var/lib/clamav

    sed -i "s/^LogSyslog.*/LogSyslog true/g" /etc/clamav/clamd.conf
    sed -i "s/^LogFacility.*/LogFacility LOG_MAIL/g" /etc/clamav/clamd.conf
    sed -i "s/^ScanMail.*/ScanMail yes/g" /etc/clamav/clamd.conf
    sed -i "s/^ScanArchive.*/ScanArchive yes/g" /etc/clamav/clamd.conf

    sed -i "s/^LogSyslog.*/LogSyslog true/g" /etc/clamav/freshclam.conf
    sed -i "s/^LogFacility.*/LogFacility LOG_MAIL/g" /etc/clamav/freshclam.conf
    sed -i "s/^DatabaseMirror db.local.clamav.net.*/DatabaseMirror db.es.clamav.net/g" /etc/clamav/freshclam.conf


	############
	#
	# Spamassassin
	#
	############
	echo "Configuro local.cf de spamassassin"

    # Amavis-new usa las librerias Perl de Spamassassin directamente, por lo que no 
    # es necesario arrancar el servicio (no es necesario /etc/init.d/spamd start).

	cat > /etc/spamassassin/local.cf <<EOFSPAMSASSASSIN
rewrite_header Subject *****SPAM*****

# dcc
use_dcc 1
dcc_path /usr/local/bin/dccproc
dcc_add_header 1
dcc_dccifd_path /var/dcc/libexec/dccifd

#pyzor
use_pyzor 1
pyzor_path /usr/bin/pyzor
pyzor_add_header 1

#razor
use_razor2 1
razor_config /etc/razor/razor-agent.conf

#bayes
use_bayes 1
use_bayes_rules 1
bayes_auto_learn 1

ifplugin Mail::SpamAssassin::Plugin::Shortcircuit
endif # Mail::SpamAssassin::Plugin::Shortcircuit
skip_rbl_checks         0
ok_languages            en es
ok_locales              en es
# Nota: El argumento de bayes_path es la combinación del directorio
# /data/vmail/amavis/bayes.d/ y el prefijo (bayes) de los ficheros .mutes _seen _toks
bayes_path /data/vmail/amavis/bayes.d/bayes
EOFSPAMSASSASSIN

	mkdir -p /data/vmail/amavis/
	mkdir -p /data/vmail/amavis/bayes.d
	chown amavis:amavis /data/vmail/amavis/bayes.d
	if [ ! -f /data/vmail/amavis/bayes.d/bayes_seen ]; then 
		sa-learn --sync –p /etc/mail/spamassassin/local.cf
	fi
	chmod 755 /data/vmail/amavis/bayes.d
	chmod 764 /data/vmail/amavis/bayes.d/*
	chown -R amavis:amavis /data/vmail/amavis/bayes.d

	# Actualizo spamassassin
	#
	echo "Actualizo keys de spamassassin"
	mkdir /etc/spamassassin/sa-update-keys
	chmod 700 /etc/spamassassin/sa-update-keys
	wget -q http://spamassassin.apache.org/updates/GPG.KEY
	sh /usr/bin/sa-update --import GPG.KEY
	sh /usr/bin/sa-update


	############
	#
	# Actualizo las firmas con freshclam
	#
	############
	echo "Actualizo las firmas con freshclam"
	/usr/bin/freshclam

	############
	#
	# Programo sa-learn
	#
	############
	#
	# En mi caso utilizo extensivamente sa-learn para que vaya aprendiendo y
	# lo hago manualmente, es decir, he dedicado una carpeta al mail MALO y
	# cada cierto tiempo voy instruyendo con el comando sa-learn. 
	#
	# El proceso lo he automatizado de la siguiente forma:
	#
	# Una vez al día analizo la carpeta cuarentena que identifico como mail
	# del tipo "MALO (spam)" para actualizar la base de datos. No borro los
	# mails de spam a posta, para que este proceso "refuerce" que son spam. 
	# Dejo comentada la línea a ejecutar para borrarlos, ojo que 
	# es destructiva
	#
	# Cada domingo, a las 2:00 am, analizo el correo BUENO (ham) usando una
	# carpeta donde voy archivando todo mi mail antiguo. 
	#
	# Para averiguar cuanto mail BUENO y MALO se aprende, arrancar el 
	# contenedor manualmente y usar el comando: sa-learn --dump magic
	#
	#
	cat > /root/instala-en-cron.txt <<EOFCRON_INSTALA
0 2 * * * /root/sa-learn-bad.sh
0 2 * * 0 /root/sa-learn-good.sh
EOFCRON_INSTALA
	crontab /root/instala-en-cron.txt

	cat > /root/sa-learn-bad.sh <<EOFCRON_SA_LEARN_BAD
#!/bin/bash
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:.:/root

# MALOS - 
#
#  Nota: Editar y adecuar a tu instalación, aquí he puesto el directorio que utilizo 
#        en mi caso para archivar correo que considero como "MALO"
#
#
sa-learn -p /etc/spamassassin/local.cf --spam /data/vmail/parchis.org/${QUARANTINE_TO}/{cur,new}

# BORRO los malotes...
# find /data/vmail/parchis.org/${QUARANTINE_TO}/{cur,new} -type f -exec rm {} \;

EOFCRON_SA_LEARN_BAD
	chmod 755 /root/sa-learn-bad.sh

	cat > /root/sa-learn-good.sh <<EOFCRON_SA_LEARN_GOOD
#!/bin/bash
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:.:/root

# BUENOS
#
#  Nota: Editar y adecuar a tu instalación, aquí he puesto el directorio que utilizo 
#        en mi caso para archivar correo antiguo que considero como "BUENO"
#
sa-learn -p /etc/spamassassin/local.cf --ham /data/vmail/luispa.com/${HAM_TO}/.LuisPa/cur

EOFCRON_SA_LEARN_GOOD
	chmod 755 /root/sa-learn-good.sh


	############
	#
	# Configurar rsyslogd para que envíe logs a un agregador remoto
	#
	############
	echo "Configuro rsyslog.conf"

    cat > /etc/rsyslog.conf <<EOFRSYSLOG
\$LocalHostName chatarrero
\$ModLoad imuxsock # provides support for local system logging
#\$ModLoad imklog   # provides kernel logging support
#\$ModLoad immark  # provides --MARK-- message capability

# provides UDP syslog reception
#\$ModLoad imudp
#\$UDPServerRun 514

# provides TCP syslog reception
#\$ModLoad imtcp
#\$InputTCPServerRun 514

# Activar para debug interactivo
#
#\$DebugFile /var/log/rsyslogdebug.log
#\$DebugLevel 2

\$ActionFileDefaultTemplate RSYSLOG_TraditionalFileFormat

\$FileOwner root
\$FileGroup adm
\$FileCreateMode 0640
\$DirCreateMode 0755
\$Umask 0022

#\$WorkDirectory /var/spool/rsyslog
#\$IncludeConfig /etc/rsyslog.d/*.conf

# Dirección del Host:Puerto agregador de Log's con Fluentd
#
*.* @@${fluentdHost}:${fluentdPort}

# Activar para debug interactivo
#
# *.* /var/log/syslog

EOFRSYSLOG

	############
	#
	# Supervisor
	# 
	############
	echo "Configuro supervisord.conf"

	cat > /etc/supervisor/conf.d/supervisord.conf <<EOF
[unix_http_server]
file=/var/run/supervisor.sock 					; path to your socket file

[inet_http_server]
port = 0.0.0.0:9001								; allow to connect from web browser to supervisord

[supervisord]
logfile=/var/log/supervisor/supervisord.log 	; supervisord log file
logfile_maxbytes=50MB 							; maximum size of logfile before rotation
logfile_backups=10 								; number of backed up logfiles
loglevel=error 									; info, debug, warn, trace
pidfile=/var/run/supervisord.pid 				; pidfile location
minfds=1024 									; number of startup file descriptors
minprocs=200 									; number of process descriptors
user=root 										; default user
childlogdir=/var/log/supervisor/ 				; where child log files will live

nodaemon=false 									; run supervisord as a daemon when debugging
;nodaemon=true 									; run supervisord interactively (production)
 
[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface
 
[supervisorctl]
serverurl=unix:///var/run/supervisor.sock		; use a unix:// URL for a unix socket 

[program:clamd]
process_name = clamd
directory = /
command = /etc/init.d/clamav-daemon start
startsecs = 0
autorestart = false

[program:freshclam]
process_name = freshclam
directory = /
command = /etc/init.d/clamav-freshclam start
startsecs = 0
autorestart = false

[program:amavisd-new]
process_name = master
directory = /
command = /usr/sbin/amavisd-new
startsecs = 0
autorestart = false

[program:rsyslog]
process_name = rsyslogd
command=/usr/sbin/rsyslogd -n
startsecs = 0
autorestart = true

[program:cron]
process_name = cron
command=/usr/sbin/cron -f
startsecs = 0
autorestart = true

#
# DESCOMENTAR PARA DEBUG o SI QUIERES SSHD
#
#[program:sshd]
#process_name = sshd
#command=/usr/sbin/sshd -D
#startsecs = 0
#autorestart = true

EOF

    #
    # Creo el fichero de control para que el resto de 
    # ejecuciones no realice la primera configuración
    > ${CONFIG_DONE}
	echo "Termino la primera configuración del contenedor"
	
fi

##################################################################
#
# EJECUCIÓN DEL COMANDO SOLICITADO
#
##################################################################
#
exec "$@"
