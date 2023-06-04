# Will try alpine initially. Pandas may require core.
FROM python:3.11-alpine
# WORKDIR /app - Don't think this is needed, as everything comes from pypi
RUN pip3 install --no-cache-dir pwdusage
# COPY . . - or this, as we don't copy any files in.
CMD ["python3", "-m", "pwdusage.server"]
EXPOSE 9050 
