#!/bin/bash

if [ -n "$VNC_PASSWORD" ]; then
    echo -n "$VNC_PASSWORD" > /.password1
    x11vnc -storepasswd $(cat /.password1) /.password2
    chmod 400 /.password*
    sed -i 's/^command=x11vnc.*/& -rfbauth \/.password2/' /etc/supervisor/conf.d/supervisord.conf
    export VNC_PASSWORD=
fi

if [ -n "$RESOLUTION" ]; then
    sed -i "s/1024x768/$RESOLUTION/" /usr/local/bin/xvfb.sh
fi

USER=${USER:-root}
HOME=/root
if [ "$USER" != "root" ]; then
    echo "* enable custom user: $USER"
    useradd --create-home --shell /bin/bash --user-group --groups adm,sudo $USER
    if [ -z "$PASSWORD" ]; then
        echo "  set default password to \"ubuntu\""
        PASSWORD=ubuntu
    fi
    HOME=/home/$USER
    echo "$USER:$PASSWORD" | chpasswd
    cp -r /root/{.gtkrc-2.0,.asoundrc} ${HOME}
    [ -d "/dev/snd" ] && chgrp -R adm /dev/snd
fi
sed -i "s|%USER%|$USER|" /etc/supervisor/conf.d/supervisord.conf
sed -i "s|%HOME%|$HOME|" /etc/supervisor/conf.d/supervisord.conf

# home folder
mkdir -p $HOME/.config/pcmanfm/LXDE/
ln -sf /usr/local/share/doro-lxde-wallpapers/desktop-items-0.conf $HOME/.config/pcmanfm/LXDE/
chown -R $USER:$USER $HOME

# nginx workers
sed -i 's|worker_processes .*|worker_processes 1;|' /etc/nginx/nginx.conf

# nginx ssl
if [ -n "$SSL_PORT" ] && [ -e "/etc/nginx/ssl/nginx.key" ]; then
    echo "* enable SSL"
	sed -i 's|#_SSL_PORT_#\(.*\)443\(.*\)|\1'$SSL_PORT'\2|' /etc/nginx/sites-enabled/default
	sed -i 's|#_SSL_PORT_#||' /etc/nginx/sites-enabled/default
fi

# nginx http base authentication
if [ -n "$HTTP_PASSWORD" ]; then
    echo "* enable HTTP base authentication"
    htpasswd -bc /etc/nginx/.htpasswd $USER $HTTP_PASSWORD
	sed -i 's|#_HTTP_PASSWORD_#||' /etc/nginx/sites-enabled/default
fi

# novnc websockify
ln -s /usr/local/lib/web/frontend/static/websockify /usr/local/lib/web/frontend/static/novnc/utils/websockify
chmod +x /usr/local/lib/web/frontend/static/websockify/run

#wahu
if [[ -v ENABLE_SSH ]]; then
    if [ ! -d /var/run/sshd ] ; then
        echo "=> Configuring sshd"
        mkdir /var/run/sshd
        # SSH login fix. Otherwise user is kicked off after login
        #sed 's/PermitRootLogin without-password/PermitRootLogin yes/' -i /etc/ssh/sshd_config
        sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd
        #sed 's/UsePAM yes/#UsePAM yes/g' -i /etc/ssh/sshd_config
    fi
    if [ ! -f ~/supervisord.ssh ] ; then
        echo "=> Adding sshd to Supervisord"
        touch ~/supervisord.ssh
        echo "[program:sshd]" >> /etc/supervisor/conf.d/sshd.conf
        echo "command=/usr/sbin/sshd -D" >> /etc/supervisor/conf.d/sshd.conf
        echo "autostart=true" >> /etc/supervisor/conf.d/sshd.conf
        echo "autorestart=true" >> /etc/supervisor/conf.d/sshd.conf
        echo "startretries=3" >> /etc/supervisor/conf.d/sshd.conf
        echo "stderr_logfile=/var/log/supervisor/sshd.err.log" >> /etc/supervisor/conf.d/sshd.conf
        echo "stdout_logfile=/var/log/supervisor/sshd.out.log" >> /etc/supervisor/conf.d/sshd.conf
    fi
fi
if [[ -v ENABLE_XRDP ]]; then
    if [ ! -f ~/supervisord.xrdp ] ; then
        echo "=> Adding xrdp to Supervisord"
        touch ~/supervisord.xrdp
        echo "[program:xrdp-sesman]" >> /etc/supervisor/conf.d/xrdp.conf
        echo "command=/usr/sbin/xrdp-sesman --nodaemon" >> /etc/supervisor/conf.d/xrdp.conf
        echo "process_name = xrdp-sesman" >> /etc/supervisor/conf.d/xrdp.conf
        echo " " >> /etc/supervisor/conf.d/xrdp.conf
        echo "[program:xrdp]" >> /etc/supervisor/conf.d/xrdp.conf
        echo "command=/usr/sbin/xrdp -nodaemon" >> /etc/supervisor/conf.d/xrdp.conf
        echo "process_name = xrdp" >> /etc/supervisor/conf.d/xrdp.conf
        echo " " >> /etc/supervisor/conf.d/xrdp.conf
        sed -i '/TerminalServerUsers/d' /etc/xrdp/sesman.ini
        sed -i '/TerminalServerAdmins/d' /etc/xrdp/sesman.ini
        xrdp-keygen xrdp auto
        mkdir -p /var/run/xrdp
        chmod 2775 /var/run/xrdp
        mkdir -p /var/run/xrdp/sockdir
        chmod 3777 /var/run/xrdp/sockdir
    fi
fi
if [[ -v CREATE_USERS ]]; then
  file="/root/createusers.txt"
  if [ -f $file ]
    then
      while IFS=: read -r username password is_sudo
          do
              echo "Username: $username, Password: $password , Sudo: $is_sudo"

              if getent passwd $username > /dev/null 2>&1
                then
                  echo "User Exists"
                else
                  useradd -ms /bin/bash $username
                  echo "$username:$password" | chpasswd
                  if [ "$is_sudo" = "Y" ]
                    then
                      usermod -aG sudo $username
                  fi
              fi
      done <"$file"
  fi
fi
if [[ -v USE_MATE ]]; then
  touch ~/mate-session
  echo "mate-session" > /etc/skel/.xsession
fi
# clearup
PASSWORD=
HTTP_PASSWORD=

exec /bin/tini -- /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
