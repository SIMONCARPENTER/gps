"""gnatcheck support for GPS

This plugin adds support for gnatcheck, a coding standard checker
"""

###########################################################################
# No user customization below this line
###########################################################################

import GPS
import os
import os.path
import re
import string
import traceback
import os_utils
from gi.repository import GObject, Gtk, GLib
from gps_utils import interactive, hook
from gps_utils.gnatcheck_rules_editor import *

gnatcheck = None


class rulesSelector(Gtk.Dialog):
    """
    Dialog used to select a coding standard file before launching gnatcheck.
    """

    def __init__(self, projectname, defaultfile):
        Gtk.Dialog.__init__(
            self,
            title="Select a coding standard file",
            parent=GPS.MDI.current().pywidget().get_toplevel(),
            flags=Gtk.DialogFlags.MODAL
        )

        # OK - Cancel buttons
        self.okButton = Gtk.Button('OK')
        self.okButton.connect('clicked', self.on_ok)
        self.okButton.show()
        self.action_area.pack_start(self.okButton, True, True, 0)

        self.cancelButton = Gtk.Button('Cancel')
        self.cancelButton.connect('clicked', self.on_cancel)
        self.cancelButton.show()
        self.action_area.pack_start(self.cancelButton, True, True, 0)

        label = Gtk.Label(
            label="No check switches are defined for project {}"
                  "\nPlease enter a coding standard file containing the"
                  " desired gnatcheck rules:".format(projectname))
        label.show()
        self.vbox.pack_start(label, False, False, 0)

        hbox = Gtk.HBox()
        hbox.show()
        self.vbox.pack_start(hbox, False, False, 0)

        self.fileEntry = Gtk.Entry()
        self.fileEntry.set_editable(True)
        self.fileEntry.show()
        hbox.pack_start(self.fileEntry, True, True, 0)

        if None != defaultfile:
            self.fileEntry.set_text(defaultfile.path)
        self.fileEntry.connect('changed', self.on_file_entry_changed)
        self.on_file_entry_changed()

        button = Gtk.Button('Browse')
        button.connect('clicked', self.on_coding_standard_file_browse)
        button.show()
        hbox.pack_start(button, False, False, 0)

    def get_file(self):
        return GPS.File(self.fileEntry.get_text())

    def on_file_entry_changed(self, *args):
        """Callback when the file entry changed"""
        name = self.fileEntry.get_text()
        if name == "":
            self.okButton.set_sensitive(False)
        else:
            self.okButton.set_sensitive(True)

    def on_coding_standard_file_browse(self, *args):
        """Callback to coding standard 'Browse' button"""
        file = GPS.MDI.file_selector()
        if file.path != "":
            self.fileEntry.set_text(file.path)

    def on_ok(self, *args):
        """Callback to 'Cancel' button"""
        self.response(Gtk.ResponseType.OK)

    def on_cancel(self, *args):
        """Callback to 'Cancel' button"""
        self.response(Gtk.ResponseType.CANCEL)


class gnatCheckProc:

    """This class controls the gnatcheck execution"""

    def __init__(self):
        self.rules_file = None
        self.rules = None

        self.locations_string = "Coding Standard violations"
        self.gnatCmd = ""
        self.full_output = ""

    def updateGnatCmd(self):
        self.gnatCmd = gps_utils.get_gnat_driver_cmd()

        if self.gnatCmd == "":
            self.gnatCmd = "gnat"

        if self.gnatCmd == "":
            GPS.Console("Messages").write(
                "Error: 'gnat' is not in the path.\n")
            GPS.Console("Messages").write(
                "Error: Could not initialize the gnatcheck module.\n")

    def edit(self):
        global ruleseditor
        prev_cmd = self.gnatCmd
        self.updateGnatCmd()

        if self.gnatCmd == "":
            return

        # gnat check command changed: we reinitialize the rules list
        if prev_cmd != self.gnatCmd or self.rules is None:
            self.rules = get_supported_rules(self.gnatCmd)

        # we retrieve the coding standard file from the project
        for opt in GPS.Project.root().get_attribute_as_list(
            "default_switches", package="check", index="ada"
        ):
            res = re.split("^\-from\=(.*)$", opt)
            if len(res) > 1:
                self.rules_file = GPS.File(res[1])

        try:
            ruleseditor = rulesEditor(self.rules, self.rules_file)
            ruleseditor.run()
            fname = ruleseditor.get_filename()
            if fname != "":
                self.rules_file = fname
            ruleseditor.destroy()
        except:
            GPS.Console("Messages").write(
                "Unexpected exception in gnatcheck.py:\n%s\n" % (
                    traceback.format_exc()))

    def parse_output(self, msg):
        # gnatcheck sometimes displays incorrectly formatted warnings (not
        # handled by GPS correctly then)
        # let's reformat those here:
        # expecting "file.ext:nnn:nnn: msg"
        # receiving "file.ext:nnn:nnn msg"
        res = re.split("^([^:]*[:][0-9]+:[0-9]+)([^:0-9].*)$", msg)
        if len(res) > 3:
            msg = res[1] + ":" + res[2]
        GPS.Locations.parse(msg, self.locations_string)

        # Aggregate output in self.full_output: CodeFix needs to be looking at
        # the whole output in one go.
        self.full_output += msg + "\n"

    def on_match(self, process, matched, unmatched):
        if unmatched == "\n":
            GPS.Console("Messages").write(self.msg + unmatched)
            self.parse_output(self.msg)
            self.msg = ""
        self.msg += matched

    def on_exit(self, process, status, remaining_output):
        if self.msg != "":
            GPS.Console("Messages").write(self.msg)
            GPS.Locations.parse(self.msg, self.locations_string)
            self.parse_output(self.msg)
            self.msg = ""

        if self.full_output:
            # There is a full output: run CodeFix.
            GPS.Codefix.parse(self.locations_string, self.full_output)

    def internalSpawn(self, filestr, project, recursive=False):
        self.full_output = ""
        need_rules_file = False
        opts = project.get_attribute_as_list(
            "default_switches", package="check", index="ada")
        if len(opts) == 0:
            need_rules_file = True
            opts = GPS.Project.root().get_attribute_as_list(
                "default_switches", package="check", index="ada")
            for opt in opts:
                res = re.split("^\-from\=(.*)$", opt)
                if len(res) > 1:
                    # we cd to the root project's dir before creating the file,
                    # as this will then correctly resolve if the file is
                    # relative to the project's dir
                    olddir = GPS.pwd()
                    rootdir = GPS.Project.root().file().directory()
                    GPS.cd(rootdir)
                    self.rules_file = GPS.File(res[1])
                    GPS.cd(olddir)

        if need_rules_file:
            selector = rulesSelector(project.name(), self.rules_file)

            if selector.run() == Gtk.ResponseType.OK:
                self.rules_file = selector.get_file()
                selector.destroy()
            else:
                selector.destroy()
                return

        self.updateGnatCmd()

        if self.gnatCmd == "":
            GPS.Console("Messages").write("Error: could not find gnatcheck")
            return
        # launch gnat check with specified project
        cmd = self.gnatCmd + ' check -P """' + \
            project.file().name("Tools_Server") + '"""'

        # also analyse subprojects ?
        if recursive:
            cmd += " -U"

        # define the scenario variables
        scenario = GPS.Project.scenario_variables()
        if scenario is not None:
            for i, j in scenario.iteritems():
                cmd += ' """-X' + i + '=' + j + '"""'
        # use progress
        cmd += " -dd"

        # now specify the files to check
        cmd += " " + filestr

        if need_rules_file:
            cmd += ' -rules """-from=' + \
                self.rules_file.name("Tools_Server") + '"""'

        # clear the Checks category in the Locations view
        if GPS.Locations.list_categories().count(self.locations_string) > 0:
            GPS.Locations.remove_category(self.locations_string)

        self.msg = ""
        process = GPS.Process(
            cmd, "^.+$",
            on_match=self.on_match,
            on_exit=self.on_exit,
            progress_regexp="^ *completed (\d*) out of (\d*) .*$",
            progress_current=1,
            progress_total=2,
            remote_server="Tools_Server",
            show_command=True)

    def check_project(self, project, recursive=False):
        try:
            self.internalSpawn("", project, recursive)
        except:
            GPS.Console("Messages").write(
                "Unexpected exception in gnatcheck.py:\n%s\n" % (
                    traceback.format_exc()))

    def check_file(self, file):
        try:
            self.internalSpawn(file.name("Tools_Server"), GPS.Project.root())
        except:
            GPS.Console("Messages").write(
                "Unexpected exception in gnatcheck.py:\n%s\n" % (
                    traceback.format_exc()))

    def check_files(self, files):
        try:
            filestr = ""
            for f in files:
                filestr += '"""' + f.name("Tools_Server") + '""" '
            self.internalSpawn(filestr, GPS.Project.root())
        except:
            GPS.Console("Messages").write(
                "Unexpected exception in gnatcheck.py:\n%s\n" % (
                    traceback.format_exc()))

# Contextual menu for checking files
# The filter does some computation, and caches the result in the context so
# that we do not need to recompute it if the action is executed


class __contextualMenuData(object):
    pass


def __contextualMenuFilter(context):
    global gnatcheckproc
    data = __contextualMenuData()
    context.gnatcheck = data

    data.desttype = "none"

    data.file = context.file()
    if data.file:
        data.desttype = "file"
        if data.file.language().lower() != "ada":
            return False

        # Does this file belong to the project tree ?
        return data.file.project(False) is not None

    data.dir = context.directory()
    if data.dir:
        data.desttype = "dir"
        # check this directory contains ada sources
        srcs = GPS.Project.root().sources(True)
        found = False
        data.files = []
        for f in srcs:
            filename = f.path
            if filename.find(data.dir) == 0:
                if f.language().lower() == "ada":
                    data.files.append(f)
                    found = True
        return found

    data.project = context.project()
    if data.project:
        data.desttype = "project"
        srcs = data.project.sources(recursive=False)
        found = False
        data.files = []
        for f in srcs:
            if f.language().lower() == "ada":
                data.files.append(f)
                found = True
        return found

    return False


def __contextualMenuLabel(context):
    data = context.gnatcheck
    if data.desttype == "file":
        fmt = "Check Coding standard of <b>{}</b>"
        name = os.path.basename(data.file.path)
    elif data.desttype == "dir":
        fmt = "Check Coding standard of files in <b>{}</b>"
        name = os.path.basename(os.path.dirname(data.dir))
    elif data.desttype == "project":
        fmt = "Check Coding standard of files in <b>{}</b>"
        name = data.project.name()
    else:
        return ""
    return fmt.format(os_utils.display_name(name))


@interactive(
    name='Check Coding Standard',
    contextual=__contextualMenuLabel,
    filter=__contextualMenuFilter)
def on_activate():
    context = GPS.contextual_context()
    data = context.gnatcheck
    global gnatcheckproc
    if data.desttype == "file":
        gnatcheckproc.check_file(data.file)
    elif data.desttype == "project":
        gnatcheckproc.check_project(data.project)
    else:
        gnatcheckproc.check_files(data.files)


# create the menus instances.

gnatcheckproc = gnatCheckProc()


@interactive(name='gnatcheck root project',
             category='Coding Standard')
def check_root_project():
    "Check coding standard of the root project"
    gnatcheckproc.check_project(GPS.Project.root())


@interactive(name='gnatcheck root project recursive',
             category='Coding Standard')
def check_root_project_recursive():
    "Check coding standard fo the root project and its subprojects"
    gnatcheckproc.check_project(GPS.Project.root(), True)


@interactive(name='gnatcheck file',
             filter='Source editor',
             category='Coding Standard')
def check_file():
    "Check coding standard of the selected file"
    gnatcheckproc.check_file(GPS.EditorBuffer.get().file())


@interactive(name='edit gnatcheck rules',
             category='Coding Standard')
def edit_gnatcheck_rules():
    "Edit the coding standard file"
    gnatcheckproc.edit()


@hook('gps_started')
def __on_gps_started():
    GPS.parse_xml("""
  <tool name="GnatCheck" package="Check" index="Ada" override="false">
     <language>Ada</language>
     <switches sections="-rules">
        <check label="process RTL units" switch="-a" line="1"/>
        <check label="debug mode" switch="-d" line="1"/>
        <field label="Coding standard file"
               switch="-from"
               separator="="
               as-file="true"
               line="1"
               section="-rules"/>
     </switches>
  </tool>""")
