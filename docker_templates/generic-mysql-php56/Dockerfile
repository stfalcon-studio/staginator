FROM puppet-web-base-debian8
MAINTAINER Evgeniy Gurinovich "jeka@geek.km.ua"
ADD configs/update.sh /usr/local/bin/start.sh
RUN chmod a+x /usr/local/bin/start.sh
ADD configs/mysql_password /sbin/mysql_password
RUN chmod a+x /sbin/mysql_password
RUN chmod 777 /var/lib/php5/sessions/
RUN mkdir /stag/www/web
ADD ssh /root/.ssh
RUN chmod 700 /root/.ssh && chmod 600 /root/.ssh/id_dsa
ADD configs/htaccess /stag/www/web/.htaccess
ADD configs/log.php /stag/www/web/log.php
ADD configs/app.php /stag/www/web/app.php
RUN apt-get install -y python-requests memcached
ADD configs/slackcmd.py /usr/local/bin/slackcmd.py
RUN chmod a+x /usr/local/bin/slackcmd.py
RUN gem install cocaine
ADD configs/callback_runner.rb /usr/local/bin/callback_runner.rb
RUN chmod a+x /usr/local/bin/callback_runner.rb
ADD docker-web-terminal /var/www/docker-web-terminal
RUN chown -R www-data:www-data /var/www/docker-web-terminal
RUN usermod -d /stag www-data
CMD /usr/local/bin/start.sh 2>&1 > /stag/www/web/log.txt
