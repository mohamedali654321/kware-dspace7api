#Build base image
FROM ubuntu:18.04 as dspace_base

#Install general packages and dependencies:
RUN apt-get update && apt-get -y install openjdk-11-jdk wget nano maven ant git curl supervisor gettext-base cron && \
    update-alternatives --config java && \
#    pip install awscli && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

#Set Time Zone && postgresql:
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get update \
    && apt-get install -y postgresql

#Set DSpace image type [Test-Demo]:
ARG IMAGE_TYPE="test"
ENV IMAGE_TYPE=${IMAGE_TYPE}

#Set Pre dspace Info ARGs ,so you can pass dspace info at build time(when to build an image):
    ## DS ARGs:
ARG DS_HOST=54.220.211.123
ARG DS_PORT=3030
ARG DS_NAME="knowledgeWare DSpace7 Demo"
ARG DS_UI_HOST=54.220.211.123
ARG DS_UI_PORT=3000
ARG DS_SOLR_HOST=54.220.211.123
ARG DS_SOLR_PORT=8983
    ##DB ARGs:
ARG DB_PRE_CONFIG=false
ARG DB_HOST=54.220.211.123
ARG DB_NAME=dspace7_1
ARG DB_USER=dspace7_1
ARG DB_PASS=dspace7_1

#Set Pre Dspace Info ENVs ,so you can pass dspace info at a run time(when to run a container):
    ## DS ENVs:
ENV DS_HOST=${DS_HOST}
ENV DS_PORT=${DS_PORT}
ENV DS_NAME=${DS_NAME}
ENV DS_UI_HOST=${DS_UI_HOST}
ENV DS_UI_PORT=${DS_UI_PORT}
ENV DS_SOLR_HOST=${DS_SOLR_HOST}
ENV DS_SOLR_PORT=${DS_SOLR_PORT}
    ##DB ENVs:
ENV DB_PRE_CONFIG=${DB_PRE_CONFIG}
ENV DB_HOST=${DB_HOST}
ENV DB_NAME=${DB_NAME}
ENV DB_USER=${DB_USER}
ENV DB_PASS=${DB_PASS}

#CONFIGURE SMTP MAIL SERVER ON DSPACE:
ENV mail_server=smtp.gmail.com
ENV mail_username=dspace.mail.server@gmail.com
ENV mail_password=Dspace@dspace2019
ENV mail_port=465

#Create defualt working directory:
RUN mkdir -p /usr/local/dspace7

#Set defualt working directory:
WORKDIR /usr/local/dspace7

#Add Source Code To working directory based on $IMAGE_TYPE:
ADD . /usr/local/dspace7
RUN if [ "$IMAGE_TYPE" = "test" ] ; then rm -R /usr/local/dspace7/source ; fi

#Setting supervisor service and creating directories for copy supervisor configurations:
RUN mkdir -p /var/log/supervisor && mkdir -p /etc/supervisor/conf.d && \
    cp Dspace_pre_config/supervisor.conf /etc/supervisor.conf


###=================================================================================================================###

#Build dspace compilation image:
  ###Use dspace_base image:
FROM dspace_base as dspace_build

#Update OS Packages:
RUN apt-get update

#Add Source Code To working directory if $IMAGE_TYPE=Test:
RUN if [ "$IMAGE_TYPE" = "test" ] ; then git clone https://github.com/DSpace/DSpace.git source ; fi

#Setup dspace database and local configuration based on our ARGs from dspace_base image:
RUN sh /usr/local/dspace7/Dspace_pre_config/dspace_pre_config.build.sh

#Dspace Compilation:
RUN  cd source \
     && apt-get update \
     && mvn -U package \
     && cd ..

#Create Dspace directory:
RUN mkdir -p /dspace

#Install DSpace:
WORKDIR /usr/local/dspace7/source/dspace/target/dspace-installer
RUN ant fresh_install

#set user dspace:
#RUN useradd dspace \
#    && chown -Rv dspace: /dspace
#USER dspace

###=================================================================================================================###

#Deploy dspace to tomcat and go a live:
  ###Use dspace_base image:
FROM dspace_base as dspace_live

#Update OS Packages:
RUN apt-get update

#Create defualt working directories && install tomcat:
RUN mkdir -p /dspace /usr/local/tomcat \
     #set tomcat user:
     && groupadd tomcat && useradd -s /bin/false -g tomcat -d /usr/local/tomcat tomcat \
     && apt-get update \
     && wget https://www.apache.org/dist/tomcat/tomcat-8/v8.5.53/bin/apache-tomcat-8.5.53.tar.gz \
     && tar xvzf apache-tomcat-8.5.53.tar.gz \
     && cp -r apache-tomcat-8.5.53/* /usr/local/tomcat \
     && chown -Rv tomcat: /usr/local/tomcat \
     && rm apache-tomcat-8.5.53.tar.gz \
     && rm -r apache-tomcat-8.5.53 && apt-get clean && rm -rf /var/lib/apt/lists/*

#Add Deployment Files To working directory:
#ADD --chown=tomcat:tomcat . /dspace
COPY --chown=tomcat:tomcat --from=dspace_build /dspace /dspace

#Run dspace crontab [Scheduled Tasks via Cron]:
RUN chmod 755 Dspace_pre_config/dspace-cron \
    && /usr/bin/crontab Dspace_pre_config/dspace-cron

#Set Java Opts Env:
ENV JAVA_OPTS="-Xmx2000m -Xms2000m"
ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
ENV JRE_HOME=/usr/lib/jvm/java-11-openjdk-amd64/jre
ENV CATALINA_HOME=/usr/local/tomcat
ENV CATALINA_BASE=/usr/local/tomcat

#Set a tomcat service[make a tomcat response to service command like "service tomcat restart"]:
RUN cp Dspace_pre_config/tomcat.service /etc/init.d/tomcat \
    && chmod +x /etc/init.d/tomcat \
    && update-rc.d tomcat defaults

#Expose Tomcat Ports:
EXPOSE 8080 8005 8009 8443

#Remove Tomcat Defualt Files && Link Dspace With Tomcat:
RUN rm -rf /usr/local/tomcat/webapps/examples && \
    rm -rf /usr/local/tomcat/webapps/docs && \
    rm -rf /usr/local/tomcat/webapps/ROOT && \
    rm -rf /usr/local/tomcat/webapps/manager && \
    rm -rf /usr/local/tomcat/webapps/host-manager && \
    cp Dspace_pre_config/tomcat.server.xml /usr/local/tomcat/conf/server.xml

#RUN Tomcat && dspace pre-configuration scripts from supervisord:
CMD ["supervisord", "-c", "/etc/supervisor.conf"]

