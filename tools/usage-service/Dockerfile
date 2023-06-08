# python-alpine does not include gcc/glib required by Pandas. 
# Trying slim for now.
FROM python:3.11-slim
# Best practice is to have a WORKDIR. So we have one, but I'm pretty sure we won't
# use it.
WORKDIR /app 
RUN pip3 install --no-cache-dir pwdusage
# COPY . . -  don't need this, as we don't copy any files in.
CMD ["python3", "-m", "pwdusage.server"]
EXPOSE 9050 
