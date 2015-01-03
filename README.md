# Introducción

Contenedor base para imagen con SpamAssassin, ClamAV, AmavisD-New para "limpiar" la chatarra del correo. En este repositorio encontrarás un *contenedor Docker* para montar el "Chatarrero". Estás automatizado en el Registry Hub de Docker [luispa/base-chatarrero](https://registry.hub.docker.com/u/luispa/base-chatarrero/) conectado con el proyecto GitHub [base-chatarrero](https://github.com/LuisPalacios/base-chatarrero). 

Te recomiendo que eches un vistazo al proyecto [servicio-correo](https://github.com/LuisPalacios/servicio-correo) como ejemplo de uso.


## Ficheros

* **Dockerfile**: Para crear la base de servicio.
* **do.sh**: Para arrancar el contenedor creado con esta imagen.

## Instalación de la imagen

Para usar la imagen desde el registry de docker hub

    totobo ~ $ docker pull luispa/base-chatarrero


## Clonar el repositorio

Si quieres clonar el repositorio este es el comando poder trabajar con él directamente

    ~ $ clone https://github.com/LuisPalacios/docker-chatarrero.git

Luego puedes crear la imagen localmente con el siguiente comando

    $ docker build -t luispa/base-chatarrero ./


# Personalización

## Variables

Utilizo varias variables para poder personalizar al "chatarrero", los primeros cuatro parámetros para indicar dónde y cual es la Base de Datos de los usuarios de correo de mi sistema. Esta base de datos la creo usando postfix.admin, de hecho aquí en [base-postfixadmin](https://github.com/LuisPalacios/base-postfixadmin) te dejo un contenedor para activar tu propio servicio Web para crear dicha base de datos. 

    MAIL_DB_NAME:    Nombre de la BD de correo (creada con postfixadmin)
    MAIL_DB_USER:    Usuario de dicha BD
    MAIL_DB_PASS:    Contraseña del usuario
    MYSQL_LINK:      "mysql.tld.org:33000" dónde está dicha BD MySQL

El chatarrero tiene que hablar con el servidor SMTP, así que el siguietne parámetro indica dónde se encuentra:

    POSTFIX_LINK:    "postfix.tld.org:10025" Enlace de retorno a Postfix
    
Los cuatro parámetros siguientes se usan para configurar al chatarrero en sí:    

    MYHOSTNAME:      "tu-servidor-de-correo.tld.org"
    VIRUS_ADMIN:     "tusuario\@tudominio.com"
    QUARANTINE_TO:   "spam-cuarentena\@tudominio.com"
    HAM_TO:          "tu-archivo\@tudominio.com"

Por último, para indicar dónde deben mandarse el log uso la variable siguiente:

    FLUENTD_LINK:    "fluentd:24224" Equipo donde enviar los logs


## Volúmenes

Es importante que prepares un directorio persistente, en mi caso lo he dejado así a modo de ejemplo:

    - "/Apps/data/correo/vmail:/data/vmail"
    - "/Apps/data/correo/clamav:/var/lib/clamav"


## Troubleshooting

A continuación un ejemplo sobre cómo ejecutar manualmente el contenedor, útil para hacer troubleshooting. Ejecuto /bin/bash nada más entrar en el contenedor. 

    docker run --rm -t -i -p 22002:22 -p 10024:10024 -e FLUENTD_LINK=fluentd.tld.org:24224  -e MAIL_DB_USER=correo -e MAIL_DB_PASS=correopass -e MAIL_DB_NAME=correodb -e MYSQL_LINK="mysqlcorreo.tld.org:33000"  -v /Apps/data/correo/vmail:/data/vmail -v /Apps/data/correo/clamav:/var/lib/clamav luispa/base-chatarrero /bin/bash

Una vez arrancado ejecuto supervisord para que lance los daemons, de modo que tengo el servicio activo y estoy dentro del mismo para poder hacer troubleshooting.
	
	base-chatarrero $ docker run --rm -t -i .....
	Realizo la configuración por primera vez
	Configuro ficheros amavisd-new
	Configuro clamd.conf
	Configuro local.cf de spamassassin
	Actualizo keys de spamassassin
	Actualizo las firmas con freshclam
	ClamAV update process started at Wed Dec 31 11:29:17 2014
	main.cvd is up to date (version: 55, sigs: 2424225, f-level: 60, builder: neo)
	daily.cld is up to date (version: 19860, sigs: 1299145, f-level: 63, builder: neo)
	bytecode.cvd is up to date (version: 244, sigs: 44, f-level: 63, builder: dgoddard)
	Configuro rsyslog.conf
	Configuro supervisord.conf
	Termino la primera configuración del contenedor
	root@555a931b57bb:/#
	root@555a931b57bb:/#
	root@555a931b57bb:/# supervisord -c /etc/supervisor/supervisord.conf
	root@555a931b57bb:/#
	root@555a931b57bb:/#
