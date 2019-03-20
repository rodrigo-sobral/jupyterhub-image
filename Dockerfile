#+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-#
#       |S|c|i|e|n|c|e| |B|o|x|        #
#+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-#

# Docker file for JupyterHub image

# Build and push to Docker registry with:
#   export RELEASE_VERSION=":v0"
#   docker build -t gitlab-registry.cern.ch/swan/docker-images/jupyterhub${RELEASE_VERSION} .
#   docker login gitlab-registry.cern.ch
#   docker push gitlab-registry.cern.ch/swan/docker-images/jupyterhub${RELEASE_VERSION}


FROM gitlab-registry.cern.ch/sciencebox/docker-images/parent-images/webserver:v0

MAINTAINER Enrico Bocchi <enrico.bocchi@cern.ch>


# ----- Software versions ----- #
ARG DOCKER_VERSION="-18.06.1.ce"
ARG JUPYTERHUB_VERSION="==0.9.4"
ARG LDAPAUTHENTICATOR_VERSION="==1.2.2"
ARG DOCKERSPAWNER_VERSION="==0.10.0"
ARG KUBESPAWNER_VERSION="==0.10.1"


# ----- Install the required packages ----- #
# Install Docker (needed only by docker-compose or single-box deployment)
ADD ./repos/docker-ce.repo /etc/yum.repos.d/docker-ce.repo
RUN yum -y install \
      docker-ce$DOCKER_VERSION && \
    yum clean all && \
    rm -rf /var/cache/yum

# Install nodejs, npm, etc.
RUN yum -y install \
      nodejs \
      npm && \
    yum clean all && \
    rm -rf /var/cache/yum

# Install Python, pip, and related upgrades
RUN yum -y install \
      python36 \
      python36-libs \
      python36-pip \
      python36-setuptools && \
    yum clean all && \
    rm -rf /var/cache/yum

# Upgrade pip package manager
RUN pip3.6 install --upgrade pip

# ----- Install JupyterHub ----- #
# Install JupyterHub with upstream authenticators and spawners
RUN pip install jupyterhub$JUPYTERHUB_VERSION
RUN npm install -g configurable-http-proxy

# Upstream authenticators and spawners
RUN pip install jupyterhub-ldapauthenticator$LDAPAUTHENTICATOR_VERSION  # LDAP auth
RUN pip install dockerspawner$DOCKERSPAWNER_VERSION                     # Dockerspawner
RUN pip install jupyterhub-kubespawner$KUBESPAWNER_VERSION              # Kubespawner

#TODO: NNFP -- Remove and install separately by building on top of the produced image
# Additional authenticator: SSO to LDAP Authenticator
ADD ./jupyterhub.d/WebIdentityHandlers/SSOtoLDAPAuthenticator /tmp/SSOtoLDAPAuthenticator
WORKDIR /tmp/SSOtoLDAPAuthenticator
RUN pip install -r requirements.txt && \
    python3.6 setup.py install

#TODO: NNFP -- Remove and install separately by building on top of the produced image
# Additional authenticator: SSO Remote User Authenticator
ADD ./jupyterhub.d/WebIdentityHandlers/SSORemoteUserAuthenticator /tmp/SSORemoteUserAuthenticator
WORKDIR /tmp/SSORemoteUserAuthenticator
RUN pip install -r requirements.txt && \
    python3.6 setup.py install
WORKDIR /

# ----- Install CERN customizations ----- #
# Web GUI
RUN git clone -b master https://gitlab.cern.ch/swan/common.git /usr/local/share/jupyterhub/static/swan/

# Handlers, Spawners, Templates, ...
#TODO: 'CERNKubeSpawner' is a temporary branch. We should clone from master
RUN git clone -b CERNKubeSpawner https://gitlab.cern.ch/swan/jupyterhub.git /srv/jupyterhub/jh_gitlab
# Install CERN Handlers
WORKDIR /srv/jupyterhub/jh_gitlab/CERNHandlers
RUN pip install -r requirements.txt && \
    python3.6 setup.py install
# Install CERN Spawner
WORKDIR /srv/jupyterhub/jh_gitlab/CERNSpawner
RUN pip install -r requirements.txt && \
    python3.6 setup.py install
# Install CERN Kube Spawner
WORKDIR /srv/jupyterhub/jh_gitlab/CERNKubeSpawner
RUN pip install -r requirements.txt && \
    python3.6 setup.py install
WORKDIR /

# ----- sssd configuration ----- #
##TODO: This should go to HELM and configmaps
ADD ./sssd.d/sssd.conf /etc/sssd/sssd.conf
RUN chown root:root /etc/sssd/sssd.conf && \
    chmod 0600 /etc/sssd/sssd.conf

# ----- httpd configuration ----- #
# Disable listen directive from conf/httpd.conf and SSL default config
RUN sed -i "s/Listen 80/#Listen 80/" /etc/httpd/conf/httpd.conf && \
    mv /etc/httpd/conf.d/ssl.conf /etc/httpd/conf.d/ssl.defaults

##TODO: This should go to HELM and configmaps
# Copy plain+ssl config files and rewrites for shibboleth
ADD ./jupyterhub.d/httpd.d/jupyterhub_plain.conf.template /root/httpd_config/jupyterhub_plain.conf.template
ADD ./jupyterhub.d/httpd.d/jupyterhub_ssl.conf.template /root/httpd_config/jupyterhub_ssl.conf.template
ADD ./jupyterhub.d/httpd.d/jupyterhub_shib.conf.template /root/httpd_config/jupyterhub_shib.conf.template

# Copy SSL certificates
ADD ./secrets/boxed.crt /etc/boxed/certs/boxed.crt
ADD ./secrets/boxed.key /etc/boxed/certs/boxed.key

# ----- Shibboleth configuration ----- #
RUN mv /etc/httpd/conf.d/shib.conf /etc/httpd/conf.d/shib.noload && \
    mv /etc/shibboleth/attribute-map.xml /etc/shibboleth/attribute-map.xml.defaults && \
    mv /etc/shibboleth/shibboleth2.xml /etc/shibboleth/shibboleth2.defaults

# ----- jupyterhub configuration ----- #
# The spawner form
##TODO: This is copied from prod. Will go out of sync quickly.
ADD ./jupyterhub.d/jupyterhub_form.complete.html /srv/jupyterhub/jupyterhub_form.complete.html
ADD ./jupyterhub.d/jupyterhub_form.simple.html /srv/jupyterhub/jupyterhub_form.simple.html

# JupyterHub configuration
##TODO: This should go to HELM and configmaps
ADD ./jupyterhub.d/jupyterhub_config /root/jupyterhub_config

# Copy the list of users with administrator privileges
ADD ./jupyterhub.d/adminslist /srv/jupyterhub/adminslist

##TODO: This should be removed but requires fixes for prod
ADD ./jupyterhub.d/style.css /usr/local/share/jupyterhub/static/swan/css/style.css

# ----- Copy supervisord files ----- #
RUN mv /etc/supervisord.d/sssd.noload /etc/supervisord.d/sssd.ini && \
    mv /etc/supervisord.d/httpd.noload /etc/supervisord.d/httpd.ini
ADD ./supervisord.d/jupyterhub.ini /etc/supervisord.d/jupyterhub.ini

# ----- Run the setup script in the container ----- #
ADD ./jupyterhub.d/start.sh /root/start.sh
CMD ["/bin/bash", "/root/start.sh"]
