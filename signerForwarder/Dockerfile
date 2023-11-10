FROM alpine:3.18.4

# add openssh and clean
RUN apk add --no-cache openssh shadow

RUN adduser --system signer
# * is the hash of the password. Effectively, password login is disabled.
# but I need to do that otherwise sshd says account is locked. see:
#  https://unix.stackexchange.com/a/193131/81131
RUN usermod -p '*' signer

#allow forwarding
RUN sed -ri 's/^.*GatewayPorts.*$/GatewayPorts yes/g' /etc/ssh/sshd_config
RUN sed -ri 's/^.*AllowTcpForwarding.*$/AllowTcpForwarding yes/g' /etc/ssh/sshd_config
RUN sed -ri 's/^.*PasswordAuthentication.*$/PasswordAuthentication no/g' /etc/ssh/sshd_config
RUN sed -ri 's/^.*ClientAliveInterval.*$/ClientAliveInterval 10/g' /etc/ssh/sshd_config
RUN sed -ri 's/^.*ClientAliveCountMax.*$/ClientAliveCountMax 2/g' /etc/ssh/sshd_config
RUN printf "AllowUsers signer\n" >> /etc/ssh/sshd_config
RUN cat /etc/ssh/sshd_config

RUN mkdir /home/signer/.ssh && chown -R signer /home/signer

# Note that the container must run as root. see
#  https://superuser.com/a/1548482
CMD ["/usr/sbin/sshd", "-D", "-e"]
