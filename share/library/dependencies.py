"""Examine the project dependencies

This script will examine the dependency tree between all your projects,
and reports dependencies that are in fact not needed (and since e.g. they will
impact what's put on the linker command line, you may want to remove them),
as well as indirect dependencies (A depends on B depends on C, therefore
A should depend on C directly), which are generally better put
explicitly, although that is optional.

A project depends on another one if any of its source file depends on a
source file of the other project. This script only handles Ada source
files.

To run this script, you must first compile your project, since this script
relies on information found in the .ali files generated by the Ada compiler.

The output of this script can be viewed either as textual output in the
GPS Messages window (which you can then save to a text file, or through a
graphical tree widget, which you can dynamically manipulate.
"""

#
# No user customization below this line
#

from GPS import *
from os.path import *
import traceback
import re

Preference("Plugins/dependencies/show_source").create(
    "Show source", "boolean",
    "If enabled, show the file dependencies that explain project dependencies"
    ". If disabled, you only see the dependencies between the projects",
    False)

Preference("Plugins/dependencies/show_diff").create(
    "Show diff", "boolean",
    "If enabled, show only the differences with the current project setup."
    "This mode helps you clean up the with statements in your projects",
    True)

Preference("Plugins/dependencies/no_src_prj").create(
    "Projects with no sources", "string",
    "comma-separated list of project names that contain no sources, but are "
    "used to share common settings. Since this script looks at source files "
    "to find out dependencies, the dependencies on such projects would not "
    "be shown otherwise.",
    "shared")

show_single_file = True
# If True, we show a single file dependency to explain the dependency
# between two projects. Otherwise, we show all file dependencies. Setting this
# to False will make the computation much slower though


class Output:

    def __init__(self):
        self.current_project = None

    def set_current_project(self, project):
        """Set the name of the current project in the output.
           Its list of dependencies will be output afterwards"""
        Console().write("Project " + project.name() + " depends on:\n")

    def add_dependency(self, dependency, newdep=True, removed=False):
        """Indicate a new GPS.Project dependency for the current project"""
        show_diff = Preference("Plugins/dependencies/show_diff").get()
        if removed and show_diff:
            Console().write(" - " + dependency.name() + "\n")
        elif newdep or not show_diff:
            Console().write(" + " + dependency.name() + "\n")

    def explain_dependency(self, file, depends_on):
        """Explains the last add_dependency: file depends on depends_on"""
        if Preference("Plugins/dependencies/show_source").get():
            Console().write(
                "   => {} depends on {}\n".format(
                    basename(file.name()), basename(depends_on.name())
                )
            )

    def close(self):
        pass


class XMLOutput:

    def __init__(self):
        self.xml = "<?xml version='1.0' ?>\n<projects>\n"
        self.current_project = None
        self.current_dep = None

    def close_dependency(self):
        if self.current_dep:
            self.xml = self.xml + "</dependency>\n"
            self.current_dep = None

    def close_project(self):
        self.close_dependency()
        if self.current_project:
            self.xml = self.xml + "</project>\n"
            self.current_project = None

    def set_current_project(self, project):
        self.close_project()
        self.current_project = project
        self.xml = self.xml + "<project name='" + project.name() + "'>\n"

    def add_dependency(self, dependency, newdep=True, removed=False):
        self.close_dependency()
        self.current_dep = dependency
        if removed:
            extra = "extra=' (should be removed)'"
        elif newdep:
            extra = "extra=' (should be added)'"
        else:
            extra = "extra=''"
        self.xml = self.xml + "<dependency name='" + \
            dependency.name() + "' " + extra + ">\n"

    def explain_dependency(self, file, depends_on):
        self.xml = self.xml + \
            "<file src='" + \
            file.name() + "'>" + depends_on.name() + "</file>\n"

    def parse_attrs(self, attrs):
        """Parse an XML attribute string  attr='foo' attr="bar" """
        attr = dict()
        for a in re.findall("""(\\w+)=['"](.*?)['"]\B""", attrs):
            attr[a[0]] = a[1]
        return attr

    def on_node_clicked(self, node_name, attrs, value):
        attr = self.parse_attrs(attrs)
        if node_name == "project" or node_name == "dependency":
            EditorBuffer.get(File(attr["name"] + ".gpr"))
        elif node_name == "file":
            EditorBuffer.get(File(attr["src"]))

    def parse_xml_node(self, node_name, attrs, value):
        """Return the table rows to create for a given XML node"""
        attr = self.parse_attrs(attrs)
        if node_name == "project":
            return ["<b>" + attr["name"] + "</b>", ""]
        elif node_name == "dependency":
            return ["<b>" + attr["name"] + "</b>" + attr["extra"], ""]
        elif node_name == "file":
            return [basename(attr["src"]), basename(value)]
        return []

    def close(self):
        self.close_project()
        self.xml = self.xml + "</projects>\n"
        view = XMLViewer(name="Project dependencies",
                         columns=2,
                         sorted=True,
                         parser=self.parse_xml_node,
                         on_click=self.on_node_clicked)
        view.parse_string(self.xml)
        self.xml = ""


def compute_project_dependencies(menu):
    try:
        depends_on = dict()
        current_deps = dict()
        for p in Project.root().dependencies(recursive=True):
            current_deps[p] = [cur for cur in p.dependencies(recursive=False)]
            tmp = dict()
            previous = p
            for s in p.sources(recursive=False):
                for imp in s.imports(include_implicit=True,
                                     include_system=False):
                    ip = imp.project(default_to_root=False)
                    if ip and ip != p:
                        if show_single_file:
                            if ip != previous:
                                tmp[ip] = [(s, imp)]
                        else:
                            try:
                                tmp[ip].append((s, imp))
                            except KeyError:
                                tmp[ip] = [(s, imp)]
                        previous = ip
            depends_on[p] = tmp

        no_source_projects = [
            s.strip().lower() for s in
            Preference("Plugins/dependencies/no_src_prj").get().split(",")
        ]

        for p in depends_on:
            menu.out.set_current_project(p)
            for dep in depends_on[p]:
                menu.out.add_dependency(dep, newdep=dep not in current_deps[p])
                for reason in depends_on[p][dep]:
                    menu.out.explain_dependency(reason[0], reason[1])

                try:
                    current_deps[p].remove(dep)
                except:
                    pass

            for dep in current_deps[p]:
                if dep.name().lower() not in no_source_projects:
                    menu.out.add_dependency(dep, newdep=False, removed=True)

        menu.out.close()
    except:
        Console().write("Unexpected exception " + traceback.format_exc())


def on_gps_started(hook):
    menu = Menu.create("/Project/Dependencies/Check (to console)",
                       on_activate=compute_project_dependencies)
    menu.out = Output()

    menu = Menu.create("/Project/Dependencies/Check (to XML)",
                       on_activate=compute_project_dependencies)
    menu.out = XMLOutput()

Hook("gps_started").add(on_gps_started)
