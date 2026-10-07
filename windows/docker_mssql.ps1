New-Item -ItemType Directory -Force -Path 'D:\Work\docker_data'

docker run -d --name sqlserver2017 -e "ACCEPT_EULA=Y" -e "MSSQL_PID=Developer" -e "MSSQL_SA_PASSWORD=@nime4MeOn1y" -p 1433:1433 --mount "type=bind,source=D:\Work\docker_data,target=/data" mcr.microsoft.com/mssql/server:2017-latest