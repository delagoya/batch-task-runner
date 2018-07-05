FROM alpine:3.7
LABEL name=BatchTaskRunner
RUN apk add --no-cache docker python3
RUN pip3 install -U awscli
COPY bin/* /usr/local/bin/
RUN mkdir -p /opt/funnel/examples/
COPY examples/*json /opt/funnel/examples/
WORKDIR /scratch
# CMD ["runtask.sh"]
