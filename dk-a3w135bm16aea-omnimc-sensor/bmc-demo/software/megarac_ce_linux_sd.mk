# MegaRAC CE (AMI OpenBMC) Linux SD Build
# Required inputs: REVISION, INSTALL_ROOT_BINARIES, INSTALL_ROOT_ARTIFACTS
# Optional inputs: RESTORE_INSTALL
# Entry targets: clean-sw, build-sw, install-sw

THIS_MK_ABSPATH := $(abspath $(lastword $(MAKEFILE_LIST)))
THIS_MK_DIR := $(dir $(THIS_MK_ABSPATH))

# Enable pipefail for all commands
SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

# Enable second expansion
.SECONDEXPANSION:

# Clear all built in suffixes
.SUFFIXES:

ifeq ($(strip $(INSTALL_ROOT_BINARIES)),)
$(error ERROR: INSTALL_ROOT_BINARIES was not defined before megarac_ce_linux_sd.mk was parsed)
endif

ifeq ($(strip $(INSTALL_ROOT_ARTIFACTS)),)
$(error ERROR: INSTALL_ROOT_ARTIFACTS was not defined before megarac_ce_linux_sd.mk was parsed)
endif

ifeq ($(strip $(REVISION)),)
$(error ERROR: REVISION was not set. Pass REVISION=<revision> on the command line)
endif

include $(THIS_MK_DIR)/megarac_ce_build_common.mk

ifneq ($(strip $(OPENBMC_KAS_CUSTOM_LINUX_DTS_FILE)),)
  OPENBMC_SD_OPTIONAL_DTB := $(INSTALL_ROOT_BINARIES)/software/megarac_ce_linux_sd/$(basename $(OPENBMC_KAS_CUSTOM_LINUX_DTS_FILE)).dtb
else
  OPENBMC_SD_OPTIONAL_DTB :=
endif

OPENBMC_SD_WIC     := $(OPENBMC_SD_IMAGE_DIR)/obmc-phosphor-image-$(OPENBMC_KAS_MACHINE).wic
OPENBMC_SD_SPL_HEX := $(OPENBMC_SD_IMAGE_DIR)/u-boot-spl-dtb.hex

$(OPENBMC_SD_WIC): output_files/$(REVISION).core.rbf
	cd software/megarac_ce && ./build.sh $(abspath $<) sd

	# Skip when the stripped machine name equals the original (source == destination)
	if [ "$(OPENBMC_KAS_MACHINE)" != "$(OPENBMC_KAS_MACHINE_STRIP)" ]; then \
		cd $(OPENBMC_SD_IMAGE_DIR) && \
			for ext in wic tar.xz manifest; do \
				if [ -f obmc-phosphor-image-$(OPENBMC_KAS_MACHINE).$$ext ]; then \
					cp -f obmc-phosphor-image-$(OPENBMC_KAS_MACHINE).$$ext obmc-phosphor-image-$(OPENBMC_KAS_MACHINE_STRIP).$$ext; \
				fi; \
			done; \
	fi

output_files/%_megarac_ce_linux_sd.sof : output_files/%.sof $(OPENBMC_SD_WIC)
	quartus_pfg -c -o hps_path=$(OPENBMC_SD_SPL_HEX) $< $@

$(INSTALL_ROOT_BINARIES)/%_megarac_ce_linux_sd.sof : output_files/%_megarac_ce_linux_sd.sof | $(INSTALL_ROOT_BINARIES)
	cp -f $< $@

$(INSTALL_ROOT_BINARIES)/software/megarac_ce_linux_sd/sdimage.tar.gz: $(OPENBMC_SD_WIC) | $(INSTALL_ROOT_BINARIES)
	mkdir -p $(dir $@)
	tar -chzf $@ -C $(dir $<) $(notdir $<)

$(INSTALL_ROOT_BINARIES)/software/megarac_ce_linux_sd/sdimage.tar.gz.md5sum: \
	$(INSTALL_ROOT_BINARIES)/software/megarac_ce_linux_sd/sdimage.tar.gz
	cd $(dir $@) && md5sum $(notdir $(basename $@)) > $(notdir $@)

$(INSTALL_ROOT_BINARIES)/software/megarac_ce_linux_sd/%: $(OPENBMC_SD_IMAGE_DIR)/% | $(INSTALL_ROOT_BINARIES)
	mkdir -p $(dir $@)
	cp -f $< $@

# NOTE: megarac_ce still use old scarthgap which does not have u-boot.dtb artifact
OPENBMC_SD_ARTIFACT_FILES := \
	u-boot-spl \
	u-boot-spl.dtb \
	u-boot-spl.map \
	u-boot \
	$(OPENBMC_KAS_LINUX_DTB) \
	obmc-phosphor-image-$(OPENBMC_KAS_MACHINE_STRIP).tar.xz

$(INSTALL_ROOT_ARTIFACTS)/software/megarac_ce_linux_sd/%: $(OPENBMC_SD_IMAGE_DIR)/% | $(INSTALL_ROOT_ARTIFACTS)
	mkdir -p $(dir $@)
	cp -f $< $@

.PHONY: sd-megarac_ce-postprocess
sd-megarac_ce-postprocess: output_files/$(REVISION)_megarac_ce_linux_sd.sof output_files/$(REVISION).sof
	cp -f software/megarac_ce/scripts/* $(OPENBMC_SD_IMAGE_DIR)
	cp -f output_files/$(REVISION)_megarac_ce_linux_sd.sof $(OPENBMC_SD_IMAGE_DIR)
	cp -f output_files/$(REVISION).sof $(OPENBMC_SD_IMAGE_DIR)

	cd $(OPENBMC_SD_IMAGE_DIR) && \
		./uboot_bin.sh && \
		cp $(REVISION)_megarac_ce_linux_sd.sof ghrd.sof && \
		quartus_pfg -c qspi_helper.pfg && \
		quartus_pfg -c ghrd.sof ghrd.jic -o device=MT25QU128 -o flash_loader=A3CW135BM16AE6S -o hps_path=u-boot-spl-dtb.hex -o mode=ASX4 -o hps=1 && \
		quartus_pfg -o hps=ON -c -o hps_path=u-boot-spl-dtb.hex $(REVISION).sof ghrd.rbf

	mkdir -p $(INSTALL_ROOT_BINARIES)/software/megarac_ce_linux_sd
	cp -f $(OPENBMC_SD_IMAGE_DIR)/qspi_helper.pfg $(INSTALL_ROOT_BINARIES)/software/megarac_ce_linux_sd/
	cp -f $(OPENBMC_SD_IMAGE_DIR)/uboot_bin.sh $(INSTALL_ROOT_BINARIES)/software/megarac_ce_linux_sd/
	cp -f $(OPENBMC_SD_IMAGE_DIR)/u-boot.bin $(INSTALL_ROOT_BINARIES)/software/megarac_ce_linux_sd/
	cp -f $(OPENBMC_SD_IMAGE_DIR)/u-boot-spl $(INSTALL_ROOT_BINARIES)/software/megarac_ce_linux_sd/
	cp -f $(OPENBMC_SD_IMAGE_DIR)/qspi_helper.hps.jic $(INSTALL_ROOT_BINARIES)/software/megarac_ce_linux_sd/
	cp -f $(OPENBMC_SD_IMAGE_DIR)/ghrd.hps.jic $(INSTALL_ROOT_BINARIES)/software/megarac_ce_linux_sd/
	cp -f $(OPENBMC_SD_IMAGE_DIR)/ghrd.core.rbf $(INSTALL_ROOT_BINARIES)/software/megarac_ce_linux_sd/
	cp -f $(OPENBMC_SD_IMAGE_DIR)/ghrd.hps.rbf $(INSTALL_ROOT_BINARIES)/software/megarac_ce_linux_sd/

.PHONY: clean-sw
clean-sw:
	cd software/megarac_ce && ./clean_build.sh

.PHONY: build-sw
build-sw: $(OPENBMC_SD_WIC)

OPENBMC_SD_INSTALL_FILES := \
	$(INSTALL_ROOT_BINARIES)/software/megarac_ce_linux_sd/sdimage.tar.gz \
	$(INSTALL_ROOT_BINARIES)/software/megarac_ce_linux_sd/sdimage.tar.gz.md5sum \
	$(INSTALL_ROOT_BINARIES)/software/megarac_ce_linux_sd/obmc-phosphor-image-$(OPENBMC_KAS_MACHINE_STRIP).tar.xz \
	$(INSTALL_ROOT_BINARIES)/software/megarac_ce_linux_sd/obmc-phosphor-image-$(OPENBMC_KAS_MACHINE_STRIP).manifest \
	$(INSTALL_ROOT_BINARIES)/software/megarac_ce_linux_sd/Image \
	$(INSTALL_ROOT_BINARIES)/software/megarac_ce_linux_sd/kernel.itb \
	$(OPENBMC_SD_OPTIONAL_DTB) \
	$(INSTALL_ROOT_BINARIES)/software/megarac_ce_linux_sd/u-boot-spl-dtb.bin \
	$(INSTALL_ROOT_BINARIES)/software/megarac_ce_linux_sd/u-boot-spl-dtb.hex \
	$(INSTALL_ROOT_BINARIES)/software/megarac_ce_linux_sd/boot.scr.uimg \
	$(INSTALL_ROOT_BINARIES)/software/megarac_ce_linux_sd/u-boot.itb \
	$(INSTALL_ROOT_BINARIES)/software/megarac_ce_linux_sd/uboot.env \
	$(INSTALL_ROOT_BINARIES)/$(REVISION)_megarac_ce_linux_sd.sof

.PHONY: install-sw
install-sw : \
	$(OPENBMC_SD_INSTALL_FILES) \
	sd-megarac_ce-postprocess \
	$(addprefix $(INSTALL_ROOT_ARTIFACTS)/software/megarac_ce_linux_sd/, $(OPENBMC_SD_ARTIFACT_FILES))
