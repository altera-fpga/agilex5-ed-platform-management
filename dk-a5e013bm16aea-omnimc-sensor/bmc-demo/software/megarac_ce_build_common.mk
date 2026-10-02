THIS_MK_ABSPATH := $(abspath $(lastword $(MAKEFILE_LIST)))
THIS_MK_DIR := $(dir $(THIS_MK_ABSPATH))

# Enable pipefail for all commands
SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

# Enable second expansion
.SECONDEXPANSION:

# Clear all built in suffixes
.SUFFIXES:

OPENBMC_MACHINE_YML_PATH := software/megarac_ce/kas/machine.yml

OPENBMC_KAS_MACHINE := $(shell grep -A 10 "machine:" $(OPENBMC_MACHINE_YML_PATH) | grep "MACHINE" | sed -E 's/.*MACHINE = "([^"]+)".*/\1/')

# Strip _openbmc suffix for customer-facing file names (agilex5e_013b_openbmc -> agilex5e_013b)
OPENBMC_KAS_MACHINE_STRIP := $(shell echo "$(OPENBMC_KAS_MACHINE)" | sed 's/_openbmc$$//')

OPENBMC_KAS_LINUX_DTS_FILE := $(shell grep -A 10 "machine:" $(OPENBMC_MACHINE_YML_PATH) | grep -E '^\s*LINUX_DTS_FILE\s*=' | sed -E 's/.*LINUX_DTS_FILE = "([^"]+)".*/\1/')
OPENBMC_KAS_CUSTOM_LINUX_DTS_FILE := $(shell grep -A 10 "machine:" $(OPENBMC_MACHINE_YML_PATH) | grep -E '^\s*CUSTOM_LINUX_DTS_FILE\s*=' | sed -E 's/.*CUSTOM_LINUX_DTS_FILE = "([^"]+)".*/\1/')

ifeq ($(strip $(OPENBMC_KAS_MACHINE)),)
$(error ERROR: MACHINE not found in $(OPENBMC_MACHINE_YML_PATH))
endif

ifeq ($(strip $(OPENBMC_KAS_LINUX_DTS_FILE)),)
$(error ERROR: LINUX_DTS_FILE not found in $(OPENBMC_MACHINE_YML_PATH))
endif

OPENBMC_KAS_LINUX_DTB := $(basename $(OPENBMC_KAS_LINUX_DTS_FILE)).dtb

OPENBMC_SD_IMAGE_DIR := software/megarac_ce/build/tmp/deploy/images/$(OPENBMC_KAS_MACHINE)
