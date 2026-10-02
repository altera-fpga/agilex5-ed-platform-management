FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# MegaRAC web UI WITHOUT git-lfs (scarthgap-style).
#
# AMI's walnascar meta-ami/meta-core bbappends (masked in kas.yml) fetch their
# fork PLUS an LFS webui-libraries.git that ships a vendored node_modules.tar.gz
# and build offline (do_compile[network]=0) -> needs git-lfs >=3.x on the host.
#
# Here we get the same MegaRAC frontend without git-lfs: repoint SRC_URI at
# AMI's fork over https (no webui-libraries LFS repo) and run an online
# `npm install` at do_compile time (in-task network is available in this build
# environment). The MegaRAC branding comes from the fork source + AMI's .env +
# the logos/favicon shipped alongside this bbappend.
SRC_URI = "git://github.com/ocp-hm-openbmc-opf-ami/webui-vue;protocol=https;branch=main"
SRCREV = "c757b32cc2940f19429af1903d3d0bda9f20c150"

SRC_URI += " \
    file://login-company-logo.svg \
    file://logo-header.svg \
    file://favicon.ico \
    "

# npm install reaches the registry; declare the network requirement explicitly.
do_compile[network] = "1"

# Generate AMI's .env the same way meta-ami's (masked) bbappend does, so the
# MegaRAC feature flags that drive the login/menu layout are set. Without this
# the UI renders "raw" (unstyled login page). Mirrors
# meta-ami/meta-common/recipes-phosphor/webui/webui-vue_%.bbappend.
do_compile:prepend() {
    # Seed .env.intel from AMI's .env.ami (fork ships one of these).
    if [ -f ${S}/.env.ami ]; then
        cp -vf ${S}/.env.ami ${S}/.env.intel
    fi

    # Turn each EXTRA_IMAGE_FEATURES entry into VUE_APP_<FEATURE>_ENABLED="true".
    first=1
    for feature in ${EXTRA_IMAGE_FEATURES}; do
        ENV_VAR_NAME=$(echo "$feature" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
        ENV_LINE="VUE_APP_${ENV_VAR_NAME}_ENABLED=\"true\""
        if [ $first -eq 1 ]; then echo "" >> ${S}/.env.intel; first=0; fi
        if ! grep -q "^${ENV_LINE}$" ${S}/.env.intel 2>/dev/null; then
            echo "${ENV_LINE}" >> ${S}/.env.intel
        fi
    done

    # Fold any VUE_APP_* vars already in the environment into .env.intel.
    for var in $(env | awk -F= '/^VUE_APP/ {print $1}'); do
        value="$(env | grep "^${var}=" | cut -d= -f2-)"
        if grep -q "^${var}=" ${S}/.env.intel 2>/dev/null; then
            sed -i "s|^${var}=.*|${var}=\"${value}\"|" ${S}/.env.intel
        else
            echo "${var}=\"${value}\"" >> ${S}/.env.intel
        fi
    done

    if [ -f ${S}/.env.intel ]; then
        cp -vf ${S}/.env.intel ${S}/.env
    fi

    # MegaRAC branding assets.
    if [ -d ${S}/src/assets/images ]; then
        cp -vf ${UNPACKDIR}/login-company-logo.svg ${S}/src/assets/images/ || true
        cp -vf ${UNPACKDIR}/logo-header.svg ${S}/src/assets/images/ || true
    fi
    if [ -d ${S}/public ]; then
        cp -vf ${UNPACKDIR}/favicon.ico ${S}/public/ || true
    fi
}

do_compile() {
    cd ${S}
    rm -rf node_modules

    npm_proxy_args=""
    if [ -n "${http_proxy}" ]; then
        npm_proxy_args="${npm_proxy_args} --proxy=${http_proxy}"
    fi
    if [ -n "${https_proxy}" ]; then
        npm_proxy_args="${npm_proxy_args} --https-proxy=${https_proxy}"
    fi

    npm_cmd="npm"
    if [ -x /usr/bin/npm ]; then
        npm_cmd="/usr/bin/npm"
    fi

    export LANG=C
    export LC_ALL=C
    export PATH="/usr/bin:${PATH}"

    # The fork ships a full package-lock.json pinning the exact theme stack
    # (bootstrap 4.6.0 / bootstrap-vue 2.21.2 / vue 2.6.12 / sass 1.32.8). Use
    # `npm ci` to reproduce that locked tree byte-for-byte (closest match to
    # AMI's vendored node_modules without git-lfs). Do NOT pass --omit=optional
    # or --legacy-peer-deps here: they perturb the resolved tree and were the
    # cause of the mis-compiled SCSS (nav mispositioned, wrong font colours).
    # Fall back to install only if the lockfile is missing/out of sync.
    if [ -f package-lock.json ]; then
        if ! ${npm_cmd} --loglevel info ${npm_proxy_args} ci --ignore-scripts; then
            bbwarn "npm ci failed (lockfile out of sync?); falling back to npm install"
            ${npm_cmd} --loglevel info ${npm_proxy_args} install --ignore-scripts --legacy-peer-deps
        fi
    else
        ${npm_cmd} --loglevel info ${npm_proxy_args} install --ignore-scripts --legacy-peer-deps
    fi

    ${npm_cmd} run build ${EXTRA_OENPM}
}
