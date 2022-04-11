# Andy's Magical Drupal Installation script of Joy (and pain)

Installing the Drupal site without a copy of the database was quite a challenge.

In this short, executable guide I will walk through the wonderful world of installing the Drupal site.

## But first, the versions

Currently supported is

| Tool     | Version |
|----------|---------|
| php      | 7.x     |
| composer | 1.x     |

```bash
if [[ $(composer -V) == *"2."* ]]; then
  echo "Currently this project only works with composer version 1"
  exit 1
fi
```

```bash
if [[ $(php -v) != *"PHP 7."* ]]; then
  echo "Currently this project only works with php version 7"
  exit 1
fi
```

Set start bash errors and line by line echoing
```bash
# First echo each command after they are run
set -x
# Stop if there's an error
set -e
```

## Step 1: Starting fresh

For various reasons I had to have to re-run this script (since it might error out halfway through). To prevent
a half-installed drupal site from messing up the script, we can use git to cleanse our mind, our soul, and also the
`docroot` folder. I added some nice warnings here because that folder may contain people's databases, uploaded images,
and so on so I'm really hoping this doesn't delete someone's life's work.

```bash
# Use git to remove all unchecked in files in the doc root folder
if [[ $1 != "-y" ]]; then
  read -p "This script git cleans your docroot folder. Continue? (y/n)?" CONT
  if [[ $CONT != "y" ]]; then
    exit 1
  fi
fi
echo "Git cleaning all files in docroot... you have 3 seconds to cancel"
sleep 3
GIT_ASK_YESNO=false git clean -q -x -f -d docroot || true
```

## Step 2: Composer install

This installs the modules into the `docroot` folder as well as the `vendor` folder . There are these `type` annotations
which changes the install location of the dependancies, but there seems to be some sort of issue with them because
as we will see later, some dependancies get half installed. I'm not sure how composer decides what goes into `vendor`
and what goes into `docroot`.

```bash
# Use composer to install dependencies
composer install -q
```

## Step 3: Setting the configuration location

This is needed to "import" the config. This goes into default settings however I suspect that the default settings
should be copied to `settings.php` at this stage to solve a problem later. I'll have to try this at some point.

```bash
# Now the sync directory needs to be set. I'm not sure which one of these needs to change so just setting both
echo '$settings["config_sync_directory"] = "../config/sync";' >> docroot/sites/default/default.settings.php
```

## Step 4: The ultimate problem... installing from an existing configuration

The definition of "ultimate" means final. "Penultimate" means second to last. So really this isn't the ultimate problem
but the penpenpenpenpenultimate problem since it's just one of the last ones. However it is the source of a lot of problems.

So basically there's a couple ways to install a Drupal project using an existing configuration. You could:

1. Site install, then import the config. 
   1. I tried this but there was error messages about not being able to import due to existing shortcuts. I didn't try just deleting the shortcuts but I figured there would probably be a lot of errors like that.
   2. I also tried installing using the minimal profile, but the existing config I'm trying to import is using the standard one and Drupal doesn't let you switch mid-drupe (mid-drip?)
2. Install using the [config install](https://www.drupal.org/project/config_installer) software
   1. Sike! Fooled you. hahaha. Did you really think that would work?
   2. Drupal says (in bold) "There will no Drupal 9 version" and here we are trying to install the 9th version
3. Using the [`--existing-config`](https://www.drupal.org/node/2897299) option. 
   1. This would work fine except that this profile has an install hook so you get an error
   2. There is a ticket that contains patches to make this work. They aren't too polished but I was able to get one of them working through some of my own patches

[This patch referenced here](https://www.drupal.org/project/drupal/issues/2982052#comment-14261467) seemed lke the most up to date one:

```bash
# Download a path for drupal 9.4 that lets you install using existing configuration and use the patch
curl -XGET https://www.drupal.org/files/issues/2021-09-27/2982052-73.patch --output patches/existing-config-install-hook-patch.patch
pushd docroot
patch -p 1 < ../patches/existing-config-install-hook-patch.patch
popd
```

## Step 4: Fix dependency issues

This is one I'd like to try and figure out what's going on more, but for some reason during the install there is an error message
that these dependencies "do not exist". What composer installs is missing some metadata so here we will just download them
and install them manually which makes them work

```bash
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
```

Also, one dependency seems to straight up be missing or something

```bash
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
```

## Step 5: Okay, here comes the fun patches
### Patch 1: Form fix
```bash
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
```

### Patch 2:
```bash
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
```

## Oh now it all comes together: start the site installation process
```bash
## For some reason you have to do it twice. The first time generates the settings.php then the second one uses it
./vendor/bin/drush si --existing-config --db-url="sqlite://db.sqlite" -y || true

./vendor/bin/drush si --existing-config --db-url="sqlite://db.sqlite" -y

# Revert hacks after installation
patch -u -p0 -R < patches/patch-form-install.patch
patch -u -p0 -R < patches/patch-entity-storage-base.patch
```

## All done

There might be some errors in the installation like ` An error occurred while notifying the creation of the id field storage definition:`
but it seems to work anyway.

You should see a message like 

`[success] Installation complete.  User name: admin  User password: <some password>`

Now you can run

`./vendor/bin/drush runserver`

and visit [http://127.0.0.1:8888/](http://127.0.0.1:8888/) to see the running drupal instance. It will show the basic drupal
page but it will say page not found because you haven't put in a home page. You can log in on this page:

[http://127.0.0.1:8888/user/login](http://127.0.0.1:8888/user/login) using the username and password shown by the installation script.