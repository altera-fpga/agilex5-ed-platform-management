FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# 0213 is an AMI-authored patch (ramsankarr@ami.com, "213/213") we carried from
# the scarthgap tree. On AMI's walnascar CE-AMI202607 source getChannelFromIP has
# already been refactored (all hunks fail == change already upstream), so applying
# it aborts do_patch. Deferred until we verify against AMI's current source.
#SRC_URI += " \
#            file://0213-getchannelfromip-loop-index-userinfo-alignment.patch \
#           "
