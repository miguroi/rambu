FROM langflowai/langflow:1.12.3

USER root
RUN mkdir -p /opt/rambu/flows /opt/rambu/scripts
COPY langflow/flows/Rambu.json /opt/rambu/flows/Rambu.json
COPY langflow/scripts/bootstrap_flow.py /opt/rambu/scripts/bootstrap_flow.py
RUN chown -R 1000:0 /opt/rambu
USER 1000
