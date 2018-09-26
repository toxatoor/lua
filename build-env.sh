#!/bin/bash


ENV=$1

# APPS="NGINX OPENSSL PCRE LUAJIT LUAROCKS LUA_NGINX WRK"
APPS="NGINX OPENSSL PCRE LUAJIT LUAROCKS LUA_NGINX"

ROCKS="inspect"

NGINX_VERSION="1.14.0"
OPENSSL_VERSION="1.0.2p" 
PCRE_VERSION="8.42"
LUAJIT_VERSION="2.0.5"
LUAROCKS_VERSION="3.0.3"
LUA_NGINX_VERSION="v0.10.13"
WRK_VERSION="4.1.0"

NGINX_SRCFILE="nginx-${NGINX_VERSION}.tar.gz"
OPENSSL_SRCFILE="openssl-${OPENSSL_VERSION}.tar.gz"
PCRE_SRCFILE="pcre-${PCRE_VERSION}.tar.gz"
LUAJIT_SRCFILE="LuaJIT-${LUAJIT_VERSION}.tar.gz"
LUAROCKS_SRCFILE="luarocks-${LUAROCKS_VERSION}.tar.gz"
LUA_NGINX_SRCFILE="${LUA_NGINX_VERSION}.tar.gz"
WRK_SRCFILE="${WRK_VERSION}.tar.gz"

LUA_NGINX_DSTFILE="lua-nginx-module-${LUA_NGINX_SRCFILE}"
WRK_DSTFILE="wrk-${WRK_SRCFILE}"

NGINX_DOWNLOADS="http://nginx.org/download"
OPENSSL_DOWNLOADS="https://www.openssl.org/source"
PCRE_DOWNLOADS="https://ftp.pcre.org/pub/pcre"
LUAJIT_DOWNLOADS="http://luajit.org/download"
LUAROCKS_DOWNLOADS="http://luarocks.github.io/luarocks/releases"
LUA_NGINX_DOWNLOADS="https://github.com/openresty/lua-nginx-module/archive"
WRK_DOWNLOADS="https://github.com/wg/wrk/archive"

CWD=$(pwd)
ROOT=${CWD}/${ENV}

TMP=$(mktemp -d /tmp/luaenv.XXXXXX)

pushd ${TMP}

for _app in ${APPS} 
do 

 _downloads="${_app}_DOWNLOADS"
 _srcfile="${_app}_SRCFILE"
 _dstfile="${_app}_DSTFILE"



 CMD=$(eval echo curl -L -# \$${_downloads}/\$${_srcfile} ) 
 DST=$(eval echo \$${_dstfile} ) 
 if [ -z "${DST}" ] ; then DST=$(eval echo \$${_srcfile}) ; fi 
 DIR=${DST%.tar.gz}
 eval ${_app}_DIR=${DIR}

 ${CMD} > ${DST} 

 mkdir ${DIR}
 tar zxf ${DST} -C ${DIR} --strip-components=1

done 

# Build LuaJIT

pushd ${LUAJIT_DIR} 

sed -i -e "s%/usr/local%${ROOT}/luajit%g" Makefile 
make 
make install 

popd 

# Build luarocks

pushd ${LUAROCKS_DIR} 
./configure --prefix=${ROOT}/luarocks --with-lua=${ROOT}/luajit 
make bootstrap
eval $(${ROOT}/luarocks/bin/luarocks path) 
for rock in ${ROCKS} 
do 
 luarocks install ${rock}
done 

popd 

# Build nginx with Lua 

pushd ${NGINX_DIR} 

export LUAJIT_LIB=${ROOT}/luajit/lib
export LUAJIT_INC=${ROOT}/luajit/include/luajit-*

./configure --prefix=${ROOT}/nginx --with-openssl=../${OPENSSL_DIR} --add-module=../${LUA_NGINX_DIR}  --with-pcre-jit --with-pcre=../${PCRE_DIR} --with-ld-opt="-Wl,-rpath,${ROOT}/luajit/lib"
make 
make install

cat > ${ROOT}/nginx/conf/nginx.conf <<EOF
user  nginx;
worker_processes  auto;
# worker_processes  4;

error_log  logs/error.log error;

pid        logs/nginx.pid;

worker_rlimit_nofile 32768 ;

pcre_jit on ;

events {
#     use kqueue ;
    worker_connections  32768 ;
}

http {
    include       mime.types;
#    default_type  application/octet-stream;
    default_type  text/plain ;

    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for" \$http_host \$request_time ';

    access_log  logs/access.log  main;

    sendfile        on;
    #tcp_nopush     on;

    keepalive_timeout  3;

    #gzip  on;

    client_max_body_size            1m;

    proxy_buffer_size 64k;
    proxy_buffers 4 128k;
    proxy_busy_buffers_size 128k;

    lua_shared_dict data 1M;

    lua_package_path  '${ROOT}/nginx/lua/?.lua;${ROOT}/luarocks/share/lua/?/?.lua;${ROOT}/luarocks/share/lua/?/?/init.lua;;';
    lua_package_cpath '${ROOT}/nginx/lua/?.so;${ROOT}/luarocks/lib/lua/?/?.so;${ROOT}/luarocks/lib/lua/?/?/?.so;;';

    lua_code_cache off;

#    init_by_lua_file        lua/init.lua ;
#    init_worker_by_lua_file lua/init-worker.lua ;


    include conf.d/*.conf;

}
EOF

mkdir ${ROOT}/nginx/lua 
popd 

echo -ne "\n\n\n### All done, environment set in ${ENV}, use 'source ${ENV}/activate' to start\n\n\n"

rm -rf ${TMP}

