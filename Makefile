# Generic FAI makefile

include Makefile.conf
MAKEFILES := Makefile Makefile.conf

# Makefile.conf.local can override some configuration variables.
ifneq ($(wildcard Makefile.conf.local),)
include Makefile.conf.local
MAKEFILES += Makefile.conf.local
endif

all: help
help:
	@echo "\n\
Help for FAI helper\n\
\n\
Run make(1) with following arguments:\n\
\n\
 - clean:         Clean all generated files.\n\
 - conf:          Create all configuration files from *.FAI_IN files.\n\
 - update-fai-config: update fai configuration in nfsroot.\n\
 - download:	  Download all external resources.\n\
 - init:          Create FAI environment.\n\
 - update-mirror: Update debian mirror for CD generation.\n\
 - cd:            Create bootable CD.\n\
 - help:          This help screen,\n\
	"

init: conf download
	fai-setup -v
	fai-chboot -IFv default

update-fai-config:
	tar --exclude 'nfsroot/*' --exclude 'mirror/*' --exclude 'isos/*' \
                --transform 's/^\./fai/' -czf nfsroot/fai-config.tgz .
	ln -f nfsroot/fai-config.tgz nfsroot/live/filesystem.dir/var/lib/fai/fai-config.tgz

update-mirror:
	mv $(MY_NFSROOT)/live/filesystem.dir/var/tmp/base-pkgs.lis \
		$(MY_NFSROOT)/live/filesystem.dir/var/tmp/base-pkgs.lis-tmp
	touch $(MY_NFSROOT)/live/filesystem.dir/var/tmp/base-pkgs.lis

	mkdir -p $(MY_MIRROR_PATH)
	rm -rf $(MY_MIRROR_PATH)/pool $(MY_MIRROR_PATH)/dists
	fai-mirror -m 2000 -B -v $(MY_IGNORE_CLASSES) $(MY_MIRROR_PATH)

	mv $(MY_NFSROOT)/live/filesystem.dir/var/tmp/base-pkgs.lis-tmp \
		$(MY_NFSROOT)/live/filesystem.dir/var/tmp/base-pkgs.lis

cd:
	rm etc/grub.cfg
	make grub
	mkdir -p isos
	fai-cd -m $(MY_MIRROR_PATH) -f isos/debian-squeeze-cw.iso


conf: $(shell find etc config dhcp.d -type f -name '*.FAI_IN' | sed 's/\.FAI_IN//g') grub
	@./create-local-live
	if test -d puppet; then \
		rsync -ai --delete puppet nfsroot/live/filesystem.dir/var/lib ; \
	fi
	@./tools/gen-dhcp

update-puppet-config:

%: %.FAI_IN $(MAKEFILES)
	@echo "Generating $@"
	@sed \
		-e 's#@@MY_MIRROR_PATH@@#$(MY_MIRROR_PATH)#g' \
		-e 's#@@MY_INSTALL_IFACE@@#$(MY_INSTALL_IFACE)#g' \
		-e 's#@@MY_FAI_SERVER@@#$(MY_FAI_SERVER)#g' \
		-e 's#@@MY_NFSROOT@@#$(MY_NFSROOT)#g' \
		-e 's#@@MY_FAI_CONFIG_DIR@@#$(MY_FAI_CONFIG_DIR)#g' \
		-e 's#@@MY_TFTPROOT@@#$(MY_TFTPROOT)#g' \
		-e 's#@@MY_MNTPOINT@@#$(MY_MNTPOINT)#g' \
		-e 's#@@MY_FAI@@#$(MY_FAI)#g' \
		-e 's#@@MY_FAI_NFS_ROOT@@#$(MY_FAI_NFS_ROOT)#g' \
		-e 's#@@MY_FAI_ROOTPW@@#$(MY_FAI_ROOTPW)#g' \
		-e 's#@@MY_FAI_INSTALLED@@#$(MY_FAI_INSTALLED)#g' \
		-e 's#@@MY_ETCKEEPER_EMAIL@@#$(MY_ETCKEEPER_EMAIL)#g' \
	     < $< > $@
	@chmod `stat -c '%a' $<` $@

download:
	for f in $(shell git ls-files '*.URL/*'); do \
		dn=`dirname "$$f"`; \
		class=`basename "$$f"`; \
		outdir=`echo "$$dn" | sed 's/\.URL//'`; \
		mkdir -p "$$outdir"; \
		url=`cat "$$f"`; \
		if ! test -f "$$outdir/$$class"; then \
			wget "$$url" -O "$$outdir/$$class" ; \
		fi; \
	done

clean-download:
	for f in $(shell git ls-files '*.URL/*'); do \
		dn=`dirname "$$f"`; \
		class=`basename "$$f"`; \
		outdir=`echo "$$dn" | sed 's/\.URL//'`; \
		rm -f "$$outdir/$$class"; \
		rmdir "$$outdir" || true; \
	done


# kernel/Documentation/filesystems/nfs/nfsroot.txt
# ip=<client-ip>:<server-ip>:<gw-ip>:<netmask>:<hostname>:<device>:<autoconf>
# ip=10.29.0.220::10.29.0.1:255.255.255.0::eth0:none
# ifconfig eth0(1) 10.29.0.220(2) netmask 255.255.255.0(3)             up  route add default gw 10
grub: etc/grub.cfg
	@for f in config/files/etc/network/interfaces/*; do \
		ip=`/sbin/ifup --force -n -v -i $$f  -a  2>&1 | grep -B 1 'route add default' | tr  '\n' ' ' | sed -n 's/ifconfig \([^ ]\+\) \([^ ]\+\) netmask \([^ ]\+\) \+.*default gw \([^ ]\+\) .*/ip=\1:\2:\3:\4:::none/p'` ; \
		h=`basename $$f` ; \
		echo "\n\
menuentry \"Install server - $$h\" {\n\
	\tset gfxpayload=1024x768\n\
	\tlinux /boot/vmlinuz boot=live FAI_FLAGS=\"verbose,sshd,createvt\" FAI_ACTION=install hostname=$$h $$ip\n\
	\tinitrd /boot/initrd.img\n\
}\n\
	" >> $< ; \
	done

clean: clean-download
	@find dhcp.d etc config -type f -name '*.FAI_IN' -print0 | sed 's/\.FAI_IN//g' | xargs -0 rm -f
	@rm -f dhcp.d/fai.conf
