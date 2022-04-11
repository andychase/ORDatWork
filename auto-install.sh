# Install script
#
# This script installs this drupal site from the existing configuration. Hopefully all these
# hacks can be removed in the near future. I mean they are just sure to stop working pretty quickly.
#
#
if [[ $(composer -V) == *"2."* ]]; then
  echo "Currently this project only works with composer version 1"
  exit 1
fi
# First echo each command after they are run
set -x
# Stop if there's an error
set -e
# Use git to remove all unchecked in files in the doc root folder
read -p "This script git cleans your docroot folder. Continue? (y/n)?" CONT
if [ "$CONT" = "y" ]; then
  echo ""
else
  exit 1
fi
echo "Git cleaning all files in docroot... you have 3 seconds to cancel"
sleep 3
GIT_ASK_YESNO=false git clean -q -x -f -d docroot || true
# Use composer to install dependencies
composer install -q
# Now the sync directory needs to be set. I'm not sure which one of these needs to change so just setting both
echo '$settings["config_sync_directory"] = "../config/sync";' >> docroot/sites/default/default.settings.php


# Download a path for drupal 9.4 that lets you install using existing configuration and use the patch
curl -XGET https://www.drupal.org/files/issues/2021-09-27/2982052-73.patch --output patches/existing-config-install-hook-patch.patch
pushd docroot
patch -p 1 < ../patches/existing-config-install-hook-patch.patch
popd

# Another really weird issue is that these modules don't get installed correctly by composer. They are missing the .yml files that makes drupal detect them
curl -XGET https://ftp.drupal.org/files/projects/h5p-2.0.0-alpha2.tar.gz --output patches/h5p-2.0.0-alpha2.tar.gz
curl -XGET https://ftp.drupal.org/files/projects/libraries-8.x-3.0-beta2.tar.gz --output patches/libraries-8.x-3.0-beta2.tar.gz
curl -XGET https://ftp.drupal.org/files/projects/paragraphs_entity_embed-8.x-2.0-alpha2.tar.gz --output patches/paragraphs_entity_embed-8.x-2.0-alpha2.tar.gz

pushd docroot/modules/contrib
[ ! -e h5p ] || rm -fr h5p
[ ! -e libraries ] || rm -fr libraries
[ ! -e paragraphs_entity_embed ] || rm -fr paragraphs_entity_embed

tar xf ../../../patches/h5p-2.0.0-alpha2.tar.gz
tar xf ../../../patches/libraries-8.x-3.0-beta2.tar.gz
tar xf ../../../patches/paragraphs_entity_embed-8.x-2.0-alpha2.tar.gz

popd
# For some reason paragraphs entity method is called for but not included. No worries
patch -u -p0 -N << 'EOF' || true
--- config/sync/core.extension.yml      2022-04-10 23:39:22.805646400 -0700
+++ config/sync/core.extension.yml      2022-04-10 18:16:48.897271000 -0700
@@ -146,6 +146,7 @@
   page_manager: 0
   panels: 0
   paragraph_view_mode: 0
+  paragraphs_entity_embed: 0
   path: 0
   path_alias: 0
   path_file: 0
EOF

# Okay, here comes the fun patches
# Patch 1: Form fix
cat << 'EOF' > patches/patch-form-install.patch
--- docroot/core/profiles/standard/standard.profile     2022-04-10 23:15:12.762050400 -0700
+++ docroot/core/profiles/standard/standard.profile     2022-04-10 23:16:57.939560800 -0700
@@ -22,5 +22,10 @@
  */
 function standard_form_install_configure_submit($form, FormStateInterface $form_state) {
   $site_mail = $form_state->getValue('site_mail');
-  ContactForm::load('feedback')->setRecipients([$site_mail])->trustData()->save();
+  // This hook is called during installation but for some reason it doesn't work
+  try {
+    ContactForm::load('feedback')->setRecipients([$site_mail])->trustData()->save();
+  } catch (Throwable $e) {
+    echo 'Caught exception: ',  $e->getMessage(), "\n";
+  }
 }
EOF
patch -u -N -p0 < patches/patch-form-install.patch
# Patch 2:
cat << 'EOF' > patches/patch-entity-storage-base.patch
--- docroot/core/lib/Drupal/Core/Entity/EntityStorageBase.php   2022-04-10 23:22:41.514373000 -0700
+++ docroot/core/lib/Drupal/Core/Entity/EntityStorageBase.php   2022-04-10 23:14:41.451039500 -0700
@@ -482,7 +482,9 @@

     // A new entity should not already exist.
     if ($id_exists && $entity->isNew()) {
-      throw new EntityStorageException("'{$this->entityTypeId}' entity with ID '$id' already exists.");
+      // Remove this during installation since the install hook patch sometimes double calls these
+      // throw new EntityStorageException("'{$this->entityTypeId}' entity with ID '$id' already exists.");
+      return $id;
     }

     // Load the original entity, if any.
EOF
patch -u -N -p0 < patches/patch-entity-storage-base.patch

# Start the site installation process
## For some reason you have to do it twice. The first time generates the settings.php then the second one uses it
bash ./vendor/bin/drush si --existing-config --db-url="sqlite://db.sqlite" -y || true

bash ./vendor/bin/drush si --existing-config --db-url="sqlite://db.sqlite" -y

# Revert hacks after installation
patch -u -p0 -R < patches/patch-form-install.patch
patch -u -p0 -R < patches/patch-entity-storage-base.patch
