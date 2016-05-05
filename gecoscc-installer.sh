#!/bin/bash

# GECOS Control Center Installer
# Download it from http://bit.ly/gecoscc-installer

# Authors: 
#   Alfonso de Cala <alfonso.cala@juntadeandalucia.es>
#
# Copyright 2016, Junta de Andalucia
# http://www.juntadeandalucia.es/
#
# Released under EUPL License V 1.1
# http://www.osor.eu/eupl

set -u
set -e

export ORGANIZATION="Your Organization"
export ADMIN_USER_NAME='superuser'
export ADMIN_EMAIL="gecos@guadalinex.org"

export GECOS_CC_SERVER_IP="127.0.0.1"
export CHEF_SERVER_IP="127.0.0.1"

export MONGO_URL="mongodb://localhost:27017/gecoscc"

export CHEF_SERVER_PACKAGE_URL="https://packages.chef.io/stable/el/6/chef-server-11.1.7-1.el6.x86_64.rpm"
export CHEF_URL="https://localhost/"

export SUPERVISOR_USER_NAME=internal
export SUPERVISOR_PASSWORD=changeme

export GECOSCC_VERSION='2.1.10'
export GECOSCC_POLICIES_URL="https://github.com/gecos-team/gecos-workstation-management-cookbook/archive/master.zip"

export NGINX_VERSION='1.4.3'

export RUBY_GEMS_REPOSITORY_URL="http://rubygems.org"
export HELP_URL="http://forja.guadalinex.org/webs/gecos/doc/v2/doku.php"

TEMPLATES_URL="https://raw.githubusercontent.com/gecos-team/gecoscc-installer/master/templates/"

# FUNCTIONS

# Download a template, replace vars and copy it to a defined destination
# PARAMETERS: Destination full path, origin url, permissions, -subst/-nosubst for environment vars substitution
function install_template {
    filename=$(basename "$1")
    curl "$TEMPLATES_URL/$2" > /tmp/$filename.tmp
    if [ "$4" == "-subst" ] 
        then
            lines="$(cat /tmp/$filename.tmp)"
            end_offset=${#lines}
            while [[ "${lines:0:$end_offset}" =~ (.*)(\$\{([a-zA-Z_][a-zA-Z_0-9]*)\})(.*) ]] ; do
                PRE="${BASH_REMATCH[1]}"
                POST="${BASH_REMATCH[4]}${lines:$end_offset:${#lines}}"
                VARNAME="${BASH_REMATCH[3]}"
                eval 'VARVAL="$'$VARNAME'"'
                lines="$PRE$VARVAL$POST"
                end_offset=${#PRE}
            done
            echo -n "${lines}" > $1
        else
            cp /tmp/$filename.tmp $1
    fi
    chmod $3 $1
}


function install_package {
    if ! rpm -q $1;then
        yum install -y $1
    fi
}

function fix_host_name {
    IP=$(hostname -I)
    echo $IP
    if  ! grep $IP /etc/hosts; then
        echo "#Added by GECOS Control Center Installer" >> /etc/hosts
        echo "$IP       $HOSTNAME" >> /etc/hosts
    fi



}

# START: MAIN MENU

OPTION=$(whiptail --title "GECOS CC Installation" --menu "Choose an option" 12 78 6 \
"CHEF" "Install Chef server" \
"MONGODB" "Install Mongo Database." \
"NGINX" "Install NGINX Web Server." \
"CC" "Install GECOS Control Center." \
"USER" "Create Control Center Superuser." \
"POLICIES" "Load New Policies." 3>&1 1>&2 2>&3 )


case $OPTION in

    
CHEF)
    echo "INSTALLING CHEF SERVER"
TO-DO: add server name to /etc/hosts (or chef-server-reconfigure will fail)
    echo "Downloading" $CHEF_SERVER_PACKAGE_URL
    curl -L "$CHEF_SERVER_PACKAGE_URL" > /tmp/chef-server.rpm
    echo "Installing"
    rpm -Uvh /tmp/chef-server.rpm
    echo "Checking host name resolution"
    fix_host_name
    echo "Configuring"
    install_template "/etc/chef-server/chef-server.rb" chef-server.rb 644 -subst
    /opt/chef-server/bin/chef-server-ctl reconfigure
    echo "Opening port in Firewall
    lokkit -s https
    echo "CHEF SERVER INSTALLED"
    echo "Please, visit https://$CHEF_SERVER_IP and change default admin password"
;;


MONGODB)
    echo "INSTALLING MONGODB SERVER"

# Add mongodb repository
cat > /etc/yum.repos.d/mongodb.repo <<EOF
[mongodb]
name=mongodb RPM Repository
baseurl=http://downloads-distro.mongodb.org/repo/redhat/os/x86_64
enabled=1
gpgcheck=0
sslverify=1
EOF

echo "Installing mongodb package"
install_package mongodb-org
echo "Starting mongodb on boot"
install_template "/etc/init.d/mongod" mongod 755 -nosubst
chkconfig mongod on
;;


CC)
    echo "INSTALLING GECOS CONTROL CENTER"
#TO-DO: Stop supervisord before reinstalling (python file could be locked)
echo "Adding EPEL repository"
if ! rpm -q epel-release-6-8.noarch; then
    rpm -ivh http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
fi
echo "Installing python-devel and pip"
install_package python-devel 
install_package python-pip
echo "Creating a Python Virtual Environment in /opt/gecosccui-$GECOSCC_VERSION"
pip install virtualenv
cd /opt/
virtualenv gecosccui-$GECOSCC_VERSION
echo "Activating Python Virtual Environment"
cd /opt/gecosccui-$GECOSCC_VERSION
export PS1="GECOS>" 
source bin/activate
echo "Installing gevent"
pip install "https://pypi.python.org/packages/source/g/gevent/gevent-1.0.tar.gz" 
echo "Installing supervisor"
pip install supervisor
echo "Installing GECOS Control Center UI"
pip install "https://github.com/gecos-team/gecoscc-ui/archive/$GECOSCC_VERSION.tar.gz"
echo "Configuring GECOS Control Center"
install_template "/opt/gecosccui-$GECOSCC_VERSION/gecoscc.ini" gecoscc.ini 644 -subst
echo "Configuring supervisord start script"
install_template "/etc/init.d/supervisord" supervisord 755 -subst
install_template "/opt/gecosccui-$GECOSCC_VERSION/supervisord.conf" supervisord.conf 644 -subst
chkconfig supervisord on

;;


NGINX)
    echo "INSTALLING NGINX WEB SERVER"

if [ ! -e /opt/nginx/bin/nginx ]
then
    echo "Installing some development packages"
    install_package gcc
    install_package pcre-devel
    install_package openssl-devel
    cd /tmp/ 
    curl -L "http://nginx.org/download/nginx-$NGINX_VERSION.tar.gz" > /tmp/nginx-$NGINX_VERSION.tar.gz
    tar xzf /tmp/nginx-$NGINX_VERSION.tar.gz
    cd /tmp/nginx-$NGINX_VERSION
    ./configure --prefix=/opt/nginx --conf-path=/opt/nginx/etc/nginx.conf --sbin-path=/opt/nginx/bin/nginx
    make && make install
fi
echo "Creating user nginx"
adduser nginx
echo "Configuring NGINX to serve GECOS Control Center"
install_template "/opt/nginx/etc/nginx.conf" nginx.conf 644 -nosubst
if [ ! -e /opt/nginx/etc/sites-available ]; then 
    mkdir /opt/nginx/etc/sites-available/
fi
if [ ! -e /opt/nginx/etc/sites-enabled ]; then 
    mkdir /opt/nginx/etc/sites-enabled/
fi
install_template "/opt/nginx/etc/sites-available/gecoscc.conf" nginx-gecoscc.conf 644 -subst
if [ ! -e /opt/nginx/etc/sites-enabled/gecoscc.conf ]; then 
    ln -s /opt/nginx/etc/sites-available/gecoscc.conf /opt/nginx/etc/sites-enabled/
fi
echo "Starting NGINX on boot"
install_template "/etc/init.d/nginx" nginx 755 -nosubst
chkconfig nginx on
echo "Opening port in Firewall
lokkit -s http
;;


POLICIES)
    echo "INSTALLING NEW POLICIES"

echo "Uploading policies to CHEF"
if [ -e /opt/chef-server/bin/chef-server-ctl ]; then
    curl $GECOSCC_POLICIES_URL > /tmp/policies.zip
    mkdir /tmp/policies
    cd /tmp/policies
    unzip /tmp/policies.zip

    cat > /tmp/knife.rb << EOF
log_level                :info
log_location             STDOUT
node_name                '$ADMIN_USER_NAME'
client_key               '/etc/chef-server/admin.pem'
validation_client_name   'chef-validator'
validation_key           '/etc/chef-server/chef-validator.pem'
chef_server_url          $CHEF_SERVER_URL
syntax_check_cache_path  '/root/.chef/syntax_check_cache'
cookbook_path            '/tmp/policies/cookbooks'
EOF
    knife cookbook upload -c /tmp/knife.rb -a
fi

if [ -e /opt/gecosccui-$GECOSCC_VERSION/bin/pmanage ]; then
    echo "Uploading policies to Control Center"
    /opt/gecosccui-$GECOSCC_VERSION/bin/pmanage /opt/gecosccui-$GECOSCC_VERSION/gecoscc.ini import_policies -a $ADMIN_USER_NAME -k /etc/chef-server/admin.pem
fi

;;


USER)
    echo "CREATING CONTROL CENTER SUPERUSER"
    if [ -e /opt/gecosccui-$GECOSCC_VERSION/bin/pmanage ]; then
        /opt/gecosccui-$GECOSCC_VERSION/bin/pmanage /opt/gecosccui-$GECOSCC_VERSION/gecoscc.ini create_chef_administrator -u $ADMIN_USER_NAME -e $ADMIN_EMAIL -a admin -s -k /etc/chef-server/admin.pem -n
        echo "User $ADMIN_USER_NAME created"
    else
        echo "Control Center is not installed in this machine"
    fi
;;
esac

