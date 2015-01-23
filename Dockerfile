FROM sequenceiq/pam
MAINTAINER opeckojo@gmail.com
ENV REFRESHED_AT 2014-11-14

USER root

RUN rpm -ivh http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm \
  && yum -q makecache \
  && yum install -y \
  curl \
  openssh-server \
  openssh-clients \
  python-pip \
  rsync \
  sudo \
  tar \
  which \
  && /usr/bin/pip install supervisor \
  && mkdir -p /etc/supervisor/conf.d \
  && mkdir -p /var/log/supervisor

COPY config/supervisord.conf /etc/

# passwordless ssh
RUN mkdir /var/run/sshd \
  && ssh-keygen -q -N '' -t dsa -f /etc/ssh/ssh_host_dsa_key \
  && ssh-keygen -q -N '' -t rsa -f /etc/ssh/ssh_host_rsa_key \
  && ssh-keygen -q -N '' -t rsa -f /root/.ssh/id_rsa \
  && cp /root/.ssh/id_rsa.pub /root/.ssh/authorized_keys

# java
RUN curl -LO 'http://download.oracle.com/otn-pub/java/jdk/8u25-b17/jdk-8u25-linux-x64.rpm' \
  -H 'Cookie: oraclelicense=accept-securebackup-cookie' \
  && rpm -i jdk-8u25-linux-x64.rpm && rm jdk-8u25-linux-x64.rpm

RUN update-alternatives \
  --install /usr/bin/java java /usr/java/default/bin/java 180020 \
  --slave /usr/bin/keytool keytool /usr/java/default/bin/keytool \
  --slave /usr/bin/rmiregistry rmiregistry /usr/java/default/bin/rmiregistry \
  && update-alternatives \
  --install /usr/bin/javac javac /usr/java/default/bin/javac 180020 \
  --slave /usr/bin/rmic rmic /usr/java/default/bin/rmic

ENV JAVA_HOME /usr/java/default
ENV PATH $PATH:$JAVA_HOME/bin

# hadoop
RUN mkdir -p /usr/local/hadoop \
  && curl -s \
  https://archive.apache.org/dist/hadoop/common/hadoop-2.5.2/hadoop-2.5.2.tar.gz \
  | tar -xz -C /usr/local/hadoop --strip 1

ENV HADOOP_PREFIX /usr/local/hadoop
ENV HADOOP_COMMON_HOME /usr/local/hadoop
ENV HADOOP_HDFS_HOME /usr/local/hadoop
ENV HADOOP_MAPRED_HOME /usr/local/hadoop
ENV HADOOP_YARN_HOME /usr/local/hadoop
ENV HADOOP_CONF_DIR /usr/local/hadoop/etc/hadoop
ENV YARN_CONF_DIR $HADOOP_PREFIX/etc/hadoop

RUN sed -i '/^export JAVA_HOME/ s:.*:export JAVA_HOME=/usr/java/default\nexport HADOOP_PREFIX=/usr/local/hadoop\nexport HADOOP_HOME=/usr/local/hadoop\n:' $HADOOP_PREFIX/etc/hadoop/hadoop-env.sh \
  && sed -i '/^export HADOOP_CONF_DIR/ s:.*:export HADOOP_CONF_DIR=/usr/local/hadoop/etc/hadoop/:' $HADOOP_PREFIX/etc/hadoop/hadoop-env.sh \
  && mkdir $HADOOP_PREFIX/input \
  && cp $HADOOP_PREFIX/etc/hadoop/*.xml $HADOOP_PREFIX/input

# pseudo distributed
COPY config/hadoop/core-site.xml.template $HADOOP_PREFIX/etc/hadoop/core-site.xml.template
RUN sed s/HOSTNAME/localhost/ /usr/local/hadoop/etc/hadoop/core-site.xml.template > /usr/local/hadoop/etc/hadoop/core-site.xml
COPY config/hadoop/hdfs-site.xml $HADOOP_PREFIX/etc/hadoop/hdfs-site.xml

COPY config/hadoop/mapred-site.xml $HADOOP_PREFIX/etc/hadoop/mapred-site.xml
COPY config/hadoop/yarn-site.xml $HADOOP_PREFIX/etc/hadoop/yarn-site.xml

RUN $HADOOP_PREFIX/bin/hdfs namenode -format \
  && rm  /usr/local/hadoop/lib/native/* \
  && curl -Ls http://dl.bintray.com/sequenceiq/sequenceiq-bin/hadoop-native-64-2.5.0.tar \
  | tar -xz -C /usr/local/hadoop/lib/native/

COPY config/ssh_config /root/.ssh/config
RUN chmod 600 /root/.ssh/config \
  && chown root:root /root/.ssh/config

# workingaround docker.io build error
RUN ls -la /usr/local/hadoop/etc/hadoop/*-env.sh \
  && chmod +x /usr/local/hadoop/etc/hadoop/*-env.sh \
  && ls -la /usr/local/hadoop/etc/hadoop/*-env.sh

# fix the 254 error code
RUN sed -i "/^[^#]*UsePAM/ s/.*/#&/"  /etc/ssh/sshd_config \
  && echo "UsePAM no" >> /etc/ssh/sshd_config \
  && echo "Port 2122" >> /etc/ssh/sshd_config

RUN service sshd start \
  && $HADOOP_PREFIX/etc/hadoop/hadoop-env.sh \
  && $HADOOP_PREFIX/sbin/start-dfs.sh \
  && $HADOOP_PREFIX/bin/hdfs dfs -mkdir -p /user/root

RUN service sshd start \
  && $HADOOP_PREFIX/etc/hadoop/hadoop-env.sh \
  && $HADOOP_PREFIX/sbin/start-dfs.sh \
  && $HADOOP_PREFIX/bin/hdfs dfs -put $HADOOP_PREFIX/etc/hadoop/ input

RUN curl -s http://d3kbcqa49mib13.cloudfront.net/spark-1.1.0-bin-hadoop2.4.tgz | tar -xz -C /usr/local/ \
  && cd /usr/local \
  && ln -s spark-1.1.0-bin-hadoop2.4 spark \
  && mkdir /usr/local/spark/yarn-remote-client
COPY config/yarn-remote-client /usr/local/spark/yarn-remote-client

RUN service sshd start \
  && $HADOOP_PREFIX/etc/hadoop/hadoop-env.sh \
  && $HADOOP_PREFIX/sbin/start-dfs.sh \
  && $HADOOP_PREFIX/bin/hdfs dfsadmin -safemode leave \
  && $HADOOP_PREFIX/bin/hdfs dfs -put /usr/local/spark/lib /spark

ENV YARN_CONF_DIR $HADOOP_PREFIX/etc/hadoop
ENV SPARK_JAR hdfs:///spark/spark-assembly-1.1.0-hadoop2.4.0.jar
ENV SPARK_HOME /usr/local/spark
ENV PATH $PATH:$SPARK_HOME/bin:$HADOOP_PREFIX/bin

RUN mkdir -p /usr/local/flume \
  && curl -s https://archive.apache.org/dist/flume/1.5.2/apache-flume-1.5.2-bin.tar.gz \
  | tar zx -C /usr/local/flume --strip 1

COPY config/flume/flume.conf /etc/flume/flume.conf

COPY config/supervisord/* /etc/supervisor/conf.d/

# SSH ports
EXPOSE 22

# HDFS ports
EXPOSE 9000 50010 50020 50070 50075 50090 50475

# YARN ports
EXPOSE 8030 8031 8032 8033 8040 8042 8088 49707

#EXPOSE 50020 50090 50070 50010 50075 8031 8032 8033 8040 8042 49707 22 8088 8030

# Flume ports
EXPOSE 4141

COPY start-supervisor.sh /usr/bin/start-supervisor.sh
CMD ["/usr/bin/start-supervisor.sh"]
