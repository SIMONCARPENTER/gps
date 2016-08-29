------------------------------------------------------------------------------
--                                  G P S                                   --
--                                                                          --
--                     Copyright (C) 2001-2016, AdaCore                     --
--                                                                          --
-- This is free software;  you can redistribute it  and/or modify it  under --
-- terms of the  GNU General Public License as published  by the Free Soft- --
-- ware  Foundation;  either version 3,  or (at your option) any later ver- --
-- sion.  This software is distributed in the hope  that it will be useful, --
-- but WITHOUT ANY WARRANTY;  without even the implied warranty of MERCHAN- --
-- TABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public --
-- License for  more details.  You should have  received  a copy of the GNU --
-- General  Public  License  distributed  with  this  software;   see  file --
-- COPYING3.  If not, go to http://www.gnu.org/licenses for a complete copy --
-- of the license.                                                          --
------------------------------------------------------------------------------

with Ada.Characters.Handling;   use Ada.Characters.Handling;
with Ada.Containers.Doubly_Linked_Lists;
with Ada.Strings.Fixed;         use Ada.Strings.Fixed;
with Ada.Strings.Unbounded;     use Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;
with GNAT.OS_Lib;               use GNAT.OS_Lib;
with GNAT.Strings;
with GNATCOLL.Projects;         use GNATCOLL.Projects;
with GNATCOLL.Templates;
with GNATCOLL.Traces;           use GNATCOLL.Traces;
with GNATCOLL.VFS;

with Gdk.Event;                 use Gdk.Event;
with Gdk.Types;                 use Gdk.Types;
with Gdk.Types.Keysyms;         use Gdk.Types.Keysyms;
with Gdk.Window;                use Gdk.Window;

with Glib;                      use Glib;
with Glib.Object;               use Glib.Object;
with Glib.Types;                use Glib.Types;

with Gtk.Alignment;             use Gtk.Alignment;
with Gtk.Cell_Layout;           use Gtk.Cell_Layout;
with Gtk.Cell_Renderer_Text;    use Gtk.Cell_Renderer_Text;
with Gtk.Clipboard;             use Gtk.Clipboard;
with Gtk.Dialog;                use Gtk.Dialog;
with Gtk.Editable;              use Gtk.Editable;
with Gtk.Enums;                 use Gtk.Enums;
with Gtk.GEntry;                use Gtk.GEntry;
with Gtk.List_Store;            use Gtk.List_Store;
with Gtk.Menu;                  use Gtk.Menu;
with Gtk.Paned;                 use Gtk.Paned;
with Gtk.Selection_Data;        use Gtk.Selection_Data;
with Gtk.Size_Group;            use Gtk.Size_Group;
with Gtk.Text_Buffer;           use Gtk.Text_Buffer;
with Gtk.Text_Iter;             use Gtk.Text_Iter;
with Gtk.Text_View;             use Gtk.Text_View;
with Gtk.Toggle_Tool_Button;    use Gtk.Toggle_Tool_Button;
with Gtk.Toolbar;               use Gtk.Toolbar;
with Gtk.Tree_Model;            use Gtk.Tree_Model;
with Gtk.Window;                use Gtk.Window;
with Gtk.Box;                   use Gtk.Box;
with Gtk.Button;                use Gtk.Button;
with Gtk.Button_Box;            use Gtk.Button_Box;
with Gtk.Check_Button;          use Gtk.Check_Button;
with Gtk.Combo_Box;             use Gtk.Combo_Box;
with Gtk.Combo_Box_Text;        use Gtk.Combo_Box_Text;
with Gtk.Label;                 use Gtk.Label;
with Gtk.Scrolled_Window;       use Gtk.Scrolled_Window;
with Gtk.Viewport;              use Gtk.Viewport;

with Gtkada.Dialogs;            use Gtkada.Dialogs;
with Gtkada.MDI;                use Gtkada.MDI;
with Gtkada.Handlers;           use Gtkada.Handlers;
with Gtkada.Types;              use Gtkada.Types;

with GPS.Customizable_Modules;  use GPS.Customizable_Modules;
with GPS.Intl;                  use GPS.Intl;
with GPS.Kernel.Actions;        use GPS.Kernel.Actions;
with GPS.Kernel.Contexts;       use GPS.Kernel.Contexts;
with GPS.Kernel.Hooks;          use GPS.Kernel.Hooks;
with GPS.Kernel.MDI;            use GPS.Kernel.MDI;
with GPS.Kernel.Modules;        use GPS.Kernel.Modules;
with GPS.Kernel.Preferences;    use GPS.Kernel.Preferences;
with GPS.Kernel.Project;        use GPS.Kernel.Project;
with GPS.Kernel.Task_Manager;   use GPS.Kernel.Task_Manager;
with GPS.Search;                use GPS.Search;

with Commands;                  use Commands;
with Commands.Interactive;      use Commands.Interactive;
with Default_Preferences;       use Default_Preferences;
with Generic_Views;             use Generic_Views;
with GUI_Utils;                 use GUI_Utils;

with Histories;                 use Histories;
with Projects;                  use Projects;
with XML_Utils;                 use XML_Utils;

package body Vsearch is
   Me : constant Trace_Handle := Create ("Vsearch");

   Search_Module_Name : constant String := "Search";

   Mode_Hist_Key      : constant History_Key := "search_mode";
   Pattern_Hist_Key   : constant History_Key := "search_patterns";
   Replace_Hist_Key   : constant History_Key := "search_replace";
   --  The key for the histories.

   Last_Function_In_Module_Key : constant History_Key := "search_function_";
   --  The prefix used to store the name of the last search function used for
   --  each module. The name of the module is appended to form the real key.

   Select_On_Match                  : Boolean_Preference;
   Close_On_Match                   : Boolean_Preference;
   Ask_Confirmation_For_Replace_All : Boolean_Preference;
   Keep_Previous_Search_Context     : Boolean_Preference;
   --  The preferences

   H_Padding : constant Guint := 5;
   --  The horizontal padding used between widgets of a same row

   type Search_Regexp is record
      Name           : GNAT.Strings.String_Access;
      Regexp         : GNAT.Strings.String_Access;
      Case_Sensitive : Boolean;
      Is_Regexp      : Boolean;
   end record;
   type Search_Regexps_Array is array (Natural range <>) of Search_Regexp;
   type Search_Regexps_Array_Access is access Search_Regexps_Array;

   type Vsearch_Mode is (Unknown, Find_Only, Find_And_Replace);
   --  Type used to represent the different search view modes.
   --  Here is a short description of each mode:
   --
   --    . Unknown: default mode. Used to know whether we should set the mode
   --      of the search view from the history.
   --
   --    . Find_Only: the search view can only be used to find occurences
   --      (no replacing).
   --
   --    . Find_And_Replace: the search view can also be used to replace
   --      occurences.

   type Vsearch_Record is new View_Record with record
      Mode                    : Vsearch_Mode := Unknown;
      Scrolled                : Gtk_Scrolled_Window;
      View                    : Gtk_Viewport;
      Replace_Label           : Gtk_Label;
      Replace_Combo           : Gtk_Combo_Box;
      Context_Combo           : Gtk_Combo_Box_Text;
      Pattern_Combo           : Gtk_Combo_Box;
      Scope_Main_Box          : Gtk_Box;
      Scope_Selector_Box      : Gtk_Box;
      Scope_Optional_Box      : Gtk_Box;
      Scope_Selector_Combo    : Gtk_Combo_Box_Text;
      Scope_Separator_Label   : Gtk_Label;
      Scope_Selector_Optional : Gtk_Widget;
      Case_Toggle             : Gtk_Toggle_Tool_Button;
      Whole_Word_Toggle       : Gtk_Toggle_Tool_Button;
      Regexp_Toggle           : Gtk_Toggle_Tool_Button;
      Search_Next_Button      : Gtk.Button.Gtk_Button;
      Replace_Button          : Gtk.Button.Gtk_Button;
      Replace_Search_Button   : Gtk.Button.Gtk_Button;
      Replace_All_Button      : Gtk.Button.Gtk_Button;
      Search_Previous_Button  : Gtk.Button.Gtk_Button;
      Search_All_Button       : Gtk.Button.Gtk_Button;
      Replace_Only_Button     : Gtk.Button.Gtk_Button;
      Selector                : Scope_Selector;

      Find_Next               : Boolean := False;
      Selection_From          : Gtk_Text_Mark;
      Selection_To            : Gtk_Text_Mark;

      Projects                : Standard.Projects.Project_Type_Array_Access;
      --  Restrict the search to these projects

      Interactive_Context     : Root_Search_Context_Access;
      --  The search context for interactieve search and replace.
      --  It is owned by this widget.
      --  Unused for "Search All" and "Replace All", so that we can run
      --  multiple such commands in parallel, and these commands can outlive
      --  the widget.
   end record;

   overriding procedure Create_Toolbar
     (View    : not null access Vsearch_Record;
      Toolbar : not null access Gtk.Toolbar.Gtk_Toolbar_Record'Class);
   overriding procedure Create_Menu
     (View    : not null access Vsearch_Record;
      Menu    : not null access Gtk.Menu.Gtk_Menu_Record'Class);
   overriding procedure On_Create
     (Self  : not null access Vsearch_Record;
      Child : not null access GPS_MDI_Child_Record'Class);

   function Initialize
     (Self : access Vsearch_Record'Class) return Gtk_Widget;
   --  Create a new search window and returns the focus widget

   procedure Set_Vsearch_Mode
     (Self : not null access Vsearch_Record'Class;
      Mode : Vsearch_Mode);
   --  Set the mode of the given search mode, hiding or showing the widgets
   --  related with replacing depending on With_Replace.

   package Search_Views is new Generic_Views.Simple_Views
     (Module_Name            => Search_Module_Name,
      View_Name              => -"Search",
      Formal_View_Record     => Vsearch_Record,
      Formal_MDI_Child       => GPS_MDI_Child_Record,
      Reuse_If_Exist         => True,
      Hide_Rather_Than_Close => True,
      Initialize             => Initialize,
      Local_Toolbar          => True,
      Local_Config           => True,
      Position               => Position_Float,
      Group                  => Group_Consoles,
      Commands_Category      => "",  --  no automatic command
      MDI_Flags        => All_Buttons or Float_To_Main or Always_Destroy_Float,
      Areas                  => Sides_Only,
      Default_Width          => -1,
      Default_Height         => -1,
      Add_Close_Button_On_Float => True);
   use Search_Views;
   subtype Vsearch_Access is Search_Views.View_Access;

   procedure Register_Preferences (Kernel : access Kernel_Handle_Record'Class);
   --  Register the preferences associated to the search functions

   package Implements_Editable is new Glib.Types.Implements
     (Gtk.Editable.Gtk_Editable, GObject_Record, GObject);
   function "+"
     (Widget : access GObject_Record'Class)
      return Gtk.Editable.Gtk_Editable
      renames Implements_Editable.To_Interface;

   type Search_Module_Data is record
      Mask         : Search_Options_Mask;
      Factory      : Module_Search_Context_Factory;

      Selector     : Scope_Selector;
      --  Store the scope selector, which holds a reference to the scope
      --  selection widgets.
      --  We could have factories instead, but that means it would be harder
      --  to preserve the current extra information when users switch between
      --  contexts.

      Id                : Module_ID;
      Label        : GNAT.Strings.String_Access;
      In_Selection : Boolean;
   end record;

   No_Search : constant Search_Module_Data :=
     (Label             => null,
      Mask              => 0,
      Factory           => null,
      Id                => null,
      Selector => null,
      In_Selection      => False);

   procedure Set_Last_Of_Module
     (Handle      : access Kernel_Handle_Record'Class;
      Search_Data : Search_Module_Data);
   --  The Search_Data given in parameter is set as being the last one selected
   --  by the user, and will be the next one shown for the corresponding
   --  module.

   function Search_Context_From_Module
     (Id           : not null access Module_ID_Record'Class;
      Handle       : access Kernel_Handle_Record'Class;
      In_Selection : Boolean := False) return Search_Module_Data;
   --  Return the first search context that matches Id, or No_Search if there
   --  is none.

   procedure Free (Data : in out Search_Module_Data);
   --  Free the memory associated with Data

   package Search_Modules_List is new Ada.Containers.Doubly_Linked_Lists
     (Search_Module_Data);
   use Search_Modules_List;

   type Vsearch_Module_Record is new Module_ID_Record with record
      Search_Modules : Search_Modules_List.List;
      --  Global variable that contains the list of all registered search
      --  functions.

      Search_Started : Boolean := False;
      --  Whether the user has started a search (Next and Previous should work)

      Search_Regexps : Search_Regexps_Array_Access;
      --  The list of predefined regexps for the search module.

      Has_Focus_On_Click : Boolean := False;
      --  If Patern/Replace combo has focus on mouse click
   end record;
   type Vsearch_Module is access all Vsearch_Module_Record'Class;

   overriding procedure Customize
     (Module : access Vsearch_Module_Record;
      File   : GNATCOLL.VFS.Virtual_File;
      Node   : Node_Ptr;
      Level  : Customization_Level);
   overriding procedure Destroy (Module : in out Vsearch_Module_Record);
   --  See inherited documentation

   Vsearch_Module_Id : Vsearch_Module;
   --  ??? Register in the kernel, shouldn't be a global variable

   Column_Text           : constant Gint := 0;
   Column_Pattern        : constant Gint := 1;
   Column_Case_Sensitive : constant Gint := 2;
   Column_Is_Regexp      : constant Gint := 3;
   Column_Whole_Word     : constant Gint := 4;

   type Search_Specific_Context is new Interactive_Command with record
      Context : GNAT.Strings.String_Access;
   end record;
   overriding procedure Primitive_Free
     (Action : in out Search_Specific_Context);
   overriding function Execute
     (Action  : access Search_Specific_Context;
      Context : Interactive_Command_Context) return Command_Return_Type;
   --  A command that opens the search view and presets the Look In field to
   --  a specific function. If Context is null, then the previous context is
   --  preserve if the preference Keep_Previous_Search_Context is set,
   --  otherwise the context is reset depending on the current module.

   type Replace_Specific_Context is new Search_Specific_Context with
     null record;
   overriding function Execute
     (Action  : access Replace_Specific_Context;
      Context : Interactive_Command_Context) return Command_Return_Type;
   --  Same as Search_Specific_Context commands but opens the search view in
   --  the replace mode (i.e: showing the replace-related widgets).

   type Abstract_Search_Command is abstract new Interactive_Command with record
      Kernel                 : access Kernel_Handle_Record'Class;
      Search_Backward        : Boolean;

      Context                : Root_Search_Context_Access;
      Context_Is_Owned       : Boolean;
      --  This context is either:
      --  * owned and freed when the command is destroyed, when using
      --    "search all" or "replace all".
      --  * owned by the search widget for other interactive uses.

      Found                  : Boolean := False;
      Select_Editor_On_Match : Boolean;
   end record;
   overriding procedure Primitive_Free (Self : in out Abstract_Search_Command);

   type Search_Command is new Abstract_Search_Command with null record;
   overriding function Execute
     (Self    : access Search_Command;
      Context : Interactive_Command_Context) return Command_Return_Type;
   overriding function Name
     (Self    : access Search_Command) return String is ("search");

   type Replace_Command is new Abstract_Search_Command with record
      Replace_With           : GNAT.Strings.String_Access;
   end record;
   overriding procedure Primitive_Free (Self : in out Replace_Command);
   overriding function Execute
     (Self    : access Replace_Command;
      Context : Interactive_Command_Context) return Command_Return_Type;
   overriding function Name
     (Self    : access Replace_Command) return String is ("replace");

   function Create_Replace
     (Vsearch         : not null access Vsearch_Record'Class;
      All_Occurrences : Boolean)
      return access Replace_Command'Class;
   --  Create a new replace command from the settings in the dialog.
   --  Result must be freed by the caller.

   function Substitute_Label
     (Kernel : not null access GPS.Kernel.Kernel_Handle_Record'Class;
      Label  : String) return String;
   --  Substitute macros in the label of the search contexts.

   function On_Button_Press
     (Self  : access Gtk_Widget_Record'Class;
      Event : Gdk_Event_Button) return Boolean;
   --  Remember is an entry has focus at the moment of mouse click.

   function On_Button_Release
     (Self  : access Gtk_Widget_Record'Class;
      Event : Gdk_Event_Button) return Boolean;
   --  Select the full text of an entry when it is clicked by left mouse
   --  button and doesn't have focus, to help users clear the entry.

   procedure On_Vsearch_Destroy (Self : access Gtk_Widget_Record'Class);
   --  Called when the dialog is destroyed

   procedure Set_Selected_Project
     (Kernel  : not null access Kernel_Handle_Record'Class;
      Context : Selection_Context);
   --  Set the current project, from the information in Context.
   --  This also refreshes the 'context' combo box.

   procedure Refresh_Context_Combo
     (Kernel : access Kernel_Handle_Record'Class);
   --  Update the context_combo, so that missing contexts are added, and the
   --  label of existing ones is updated to show the next context (macro
   --  substitution,...)

   procedure Unchecked_Free is new Ada.Unchecked_Deallocation
     (Search_Regexps_Array, Search_Regexps_Array_Access);

   procedure Set_First_Next_Mode
     (Vsearch   : access Vsearch_Record'Class;
      Find_Next : Boolean);
   --  If Find_Next is False, a new search will be started, otherwise the next
   --  occurence of the current search will be searched.

   type Set_First_Next_Mode_Cb is new Simple_Hooks_Function with null record;
   overriding procedure Execute
     (Self   : Set_First_Next_Mode_Cb;
      Kernel : not null access Kernel_Handle_Record'Class);
   --  Aborts the current search pattern

   type On_Project_View_Changed is new Simple_Hooks_Function with null record;
   overriding procedure Execute
     (Self   : On_Project_View_Changed;
      Kernel : not null access Kernel_Handle_Record'Class);
   --  Called when the project view has changed.
   --  In such a case, we cancel any pending search, since the list of
   --  source files might have changed and thus we need to restart from
   --  scratch.

   function Key_Press
     (Vsearch : access Gtk_Widget_Record'Class;
      Event   : Gdk_Event) return Boolean;
   --  Called when a key is pressed in the pattern field.

   function Key_Press_Replace
     (Vsearch : access Gtk_Widget_Record'Class;
      Event   : Gdk_Event) return Boolean;
   --  Called when a key is pressed in the replacement field.

   procedure Register_Default_Search
     (Kernel : access GPS.Kernel.Kernel_Handle_Record'Class);
   --  Register the default search function

   function Get_Nth_Search_Module
     (Kernel : access GPS.Kernel.Kernel_Handle_Record'Class;
      Num    : Positive) return Search_Module_Data;
   --  Return the Num-th registered module, or No_Search if there is no such
   --  module.

   function Find_Module
     (Kernel : access GPS.Kernel.Kernel_Handle_Record'Class;
      Label  : String) return Search_Module_Data;
   --  Search the list of registered search functions for a matching module.
   --  No_Search is returned if no such module was found.

   function Get_Or_Create_Vsearch
     (Kernel        : access Kernel_Handle_Record'Class;
      Raise_Widget  : Boolean := False;
      Reset_Entries : Boolean := False;
      Context       : GNAT.Strings.String_Access := null;
      Mode          : Vsearch_Mode := Find_Only)
      return Vsearch_Access;
   --  Return a valid vsearch widget, creating one if necessary.
   --  If Reset_Entries is True, the fields in the dialog are reset depending
   --  on the current module. Context indicates the value that should be
   --  set for "Look In". If null, this will be set based on the current module
   --  The replace-related widgets are shown/hidden depending on Mode.

   function Create_Context
     (Vsearch         : not null access Vsearch_Record'Class;
      All_Occurrences : Boolean)
     return Root_Search_Context_Access;
   --  Create the search context based on the current contents of the GUI.
   --  Result must be freed by the caller.

   procedure Reset_Interactive_Context
     (Vsearch : not null access Vsearch_Record'Class);
   --  Free the interactive search context and reset the state of buttons

   procedure Internal_Search
     (Vsearch         : Vsearch_Access;
      All_Occurrences : Boolean := False;
      Replace         : Boolean := False);
   --  Internal implementation of search capability, used by On_Search and
   --  On_Search_Replace.

   procedure Receive_Text
     (Clipboard : not null access Gtk_Clipboard_Record'Class;
      Text      : Glib.UTF8_String);
   --  Used to paste the contents of the clibboard in the search pattern entry,
   --  when no selection can be found

   ---------------
   -- Callbacks --
   ---------------

   procedure On_Search (Object : access Gtk_Widget_Record'Class);
   --  Called when button "Find/Next" is clicked.

   procedure On_Replace (Object : access Gtk_Widget_Record'Class);
   --  Called when button "Replace" is clicked.

   procedure On_Search_Previous (Object : access Gtk_Widget_Record'Class);
   --  Called when button "Previous" is clicked.

   procedure On_Search_All (Object : access Gtk_Widget_Record'Class);
   --  Called when button "Search all" is clicked.

   procedure On_Replace_Search (Object : access Gtk_Widget_Record'Class);
   --  Called when button "Replace_Find" is clicked.

   procedure On_Replace_All (Object : access Gtk_Widget_Record'Class);
   --  Called when button "Replace_All" is clicked.

   procedure On_Context_Combo_Changed
     (Object : access Gtk_Widget_Record'Class);
   --  Called when the entry "Look in" is changed.

   type Has_Search_Filter is new Action_Filter_Record with null record;
   overriding function Filter_Matches_Primitive
     (Filter  : access Has_Search_Filter;
      Context : GPS.Kernel.Selection_Context) return Boolean;
   --  Whether a search is in progress

   type Find_Next_Command is new Interactive_Command with null record;
   overriding function Execute
     (Command : access Find_Next_Command;
      Context : Interactive_Command_Context) return Command_Return_Type;
   --  Callback for menu Edit->Search Next

   type Find_Previous_Command is new Interactive_Command with null record;
   overriding function Execute
     (Command : access Find_Previous_Command;
      Context : Interactive_Command_Context) return Command_Return_Type;
   --  Callback for menu Edit->Search Previous

   type New_Predefined_Regexp is new Simple_Hooks_Function with null record;
   overriding procedure Execute
     (Self   : New_Predefined_Regexp;
      Kernel : not null access Kernel_Handle_Record'Class);
   --  Called when a new predefined regexp has been added to the kernel.

   procedure Selection_Changed (Vsearch : access Gtk_Widget_Record'Class);
   --  Called when the selected pattern has changed, to reflect the settings
   --  for the predefined patterns

   type Search_Functions_Changed is new Simple_Hooks_Function
      with null record;
   overriding procedure Execute
     (Self   : Search_Functions_Changed;
      Kernel : not null access Kernel_Handle_Record'Class);
   --  Called when the list of registered search functions has changed.

   procedure On_Float (Search_Child : access Gtk_Widget_Record'Class);
   --  The floating state of the search widget has changed

   procedure Add_To_History_And_Combo
     (Vsearch        : not null access Vsearch_Record'Class;
      Pattern        : String;
      Whole_Word     : Boolean;
      Case_Sensitive : Boolean;
      Regexp         : Boolean);
   --  Add the current settings to the history, and updates the combo box

   procedure Add_History_To_Combo
     (Vsearch : not null access Vsearch_Record'Class;
      Value   : String);
   --  Add a history entry to the combo box.

   --------------
   -- On_Float --
   --------------

   procedure On_Float (Search_Child : access Gtk_Widget_Record'Class) is
      Child   : constant MDI_Child := MDI_Child (Search_Child);
      Vsearch : constant Vsearch_Access :=
        Search_Views.View_From_Child (Child);
   begin
      if Is_Floating (Child) then
         if Vsearch.Scrolled /= null then
            Ref (Vsearch.Scrolled);
            Vsearch.Remove (Vsearch.Scrolled);
            Vsearch.View.Reparent (Vsearch);
            Unref (Vsearch.Scrolled);
            Vsearch.Scrolled := null;
         end if;
      else
         --  Create a scrolled window and put vsearch's content in it
         if Vsearch.Scrolled = null then
            Gtk_New (Vsearch.Scrolled);
            Vsearch.Scrolled.Set_Policy (Policy_Automatic, Policy_Automatic);
            Show (Vsearch.Scrolled);

            Ref (Vsearch.View);
            Vsearch.View.Reparent (Vsearch.Scrolled);
            Vsearch.Add (Vsearch.Scrolled);
            Unref (Vsearch.View);
         end if;
      end if;
   end On_Float;

   ----------
   -- Free --
   ----------

   procedure Free (Data : in out Search_Module_Data) is
   begin
      if Data.Selector /= null then
         Unref (Gtk_Widget (Data.Selector.Get_Scope_Combo));

         if Data.Selector.Get_Optional_Widget /= null then
            Unref (Data.Selector.Get_Optional_Widget);
         end if;
      end if;

      Free (Data.Label);
   end Free;

   -------------
   -- Destroy --
   -------------

   overriding procedure Destroy (Module : in out Vsearch_Module_Record) is
   begin
      if Module.Search_Regexps /= null then
         for S in Module.Search_Regexps'Range loop
            Free (Module.Search_Regexps (S).Name);
            Free (Module.Search_Regexps (S).Regexp);
         end loop;

         Unchecked_Free (Module.Search_Regexps);
      end if;

      for M of Module.Search_Modules loop
         Free (M);
      end loop;
   end Destroy;

   -------------
   -- Execute --
   -------------

   overriding function Execute
     (Self    : access Search_Command;
      Context : Interactive_Command_Context) return Command_Return_Type
   is
      pragma Unreferenced (Context);
      Dummy    : Message_Dialog_Buttons;
      Found    : Boolean;
      Continue : Boolean;
   begin
      Self.Context.Search
        (Self.Kernel,
         Self.Search_Backward,
         Give_Focus => Self.Select_Editor_On_Match,
         Found      => Found,
         Continue   => Continue);

      Self.Found := Self.Found or else Found;

      if Continue then
         Self.Set_Progress
           ((Running,
             Get_Current_Progress (Self.Context),
             Get_Total_Progress (Self.Context)));
         return Execute_Again;
      end if;

      if not Self.Found then
         Dummy := Message_Dialog
           (Msg     => "No occurrences of '" &
            Context_Look_For (Self.Context) & "' found."
            & ASCII.LF & "in "
            & Context_Look_In (Self.Context.all),
            Title   => -"Search",
            Buttons => Button_OK,
            Parent  => Self.Kernel.Get_Main_Window);
      end if;

      return Success;
   end Execute;

   --------------------
   -- Primitive_Free --
   --------------------

   overriding procedure Primitive_Free (Self : in out Replace_Command) is
   begin
      Free (Self.Replace_With);
      Primitive_Free (Abstract_Search_Command (Self));  -- inherited
   end Primitive_Free;

   overriding procedure Primitive_Free
     (Self : in out Abstract_Search_Command) is
   begin
      if Self.Context_Is_Owned then
         Free (Self.Context);
      end if;
      Primitive_Free (Interactive_Command (Self));  --  inherited
   end Primitive_Free;

   -------------
   -- Execute --
   -------------

   overriding function Execute
     (Self    : access Replace_Command;
      Context : Interactive_Command_Context) return Command_Return_Type
   is
      pragma Unreferenced (Context);
   begin
      if Replace
        (Context         => Self.Context,
         Kernel          => Self.Kernel,
         Replace_String  => Self.Replace_With.all,
         Case_Preserving => True,
         Search_Backward => Self.Search_Backward,
         Give_Focus      => Self.Select_Editor_On_Match)
      then
         Self.Set_Progress
           ((Running,
             Get_Current_Progress (Self.Context),
             Get_Total_Progress (Self.Context)));
         return Execute_Again;
      end if;

      Insert (Self.Kernel, Get_Terminate_Message (Self.Context, Replace));
      return Success;
   end Execute;

   --------------------------
   -- Add_History_To_Combo --
   --------------------------

   procedure Add_History_To_Combo
     (Vsearch : not null access Vsearch_Record'Class;
      Value   : String)
   is
      Model : constant Gtk_List_Store := -Get_Model (Vsearch.Pattern_Combo);
      Iter  : Gtk_Tree_Iter;
   begin
      if Value /= "" then
         if Value (Value'Last) = Character'Val (127)
           and then Value'Length > 4
         then
            Iter := Add_Unique_List_Entry
              (Model, Value (Value'First .. Value'Last - 4),
               Prepend => False,
               Col     => Column_Text);
            Model.Set
              (Iter, Column_Pattern, Value (Value'First .. Value'Last - 4));
            Model.Set
              (Iter, Column_Whole_Word, Value (Value'Last - 3) = '*');
            Model.Set
              (Iter, Column_Is_Regexp, Value (Value'Last - 2) = '*');
            Model.Set
              (Iter, Column_Case_Sensitive, Value (Value'Last - 1) = '*');
         else
            Iter := Add_Unique_List_Entry
              (Model, Value, Prepend => False, Col => Column_Text);
            Model.Set (Iter, Column_Pattern, Value);
            Model.Set (Iter, Column_Case_Sensitive, False);
            Model.Set (Iter, Column_Is_Regexp, False);
            Model.Set (Iter, Column_Whole_Word, False);
         end if;
      end if;
   end Add_History_To_Combo;

   ------------------------------
   -- Add_To_History_And_Combo --
   ------------------------------

   procedure Add_To_History_And_Combo
     (Vsearch : not null access Vsearch_Record'Class;
      Pattern : String;
      Whole_Word     : Boolean;
      Case_Sensitive : Boolean;
      Regexp         : Boolean)
   is
      V : constant String :=
        Pattern
        & (if Whole_Word then '*' else ' ')
        & (if Regexp then '*' else ' ')
        & (if Case_Sensitive then '*' else ' ')
        & Character'Val (127);
   begin
      Add_To_History (Get_History (Vsearch.Kernel).all, Pattern_Hist_Key, V);
      Add_History_To_Combo (Vsearch, V);
   end Add_To_History_And_Combo;

   --------------------
   -- Create_Context --
   --------------------

   function Create_Context
     (Vsearch         : not null access Vsearch_Record'Class;
      All_Occurrences : Boolean)
      return Find_Utils.Root_Search_Context_Access
   is
      use Widget_List;
      Data           : constant Search_Module_Data :=
                         Find_Module
                           (Vsearch.Kernel,
                            Get_Active_Id (Vsearch.Context_Combo));
      Pattern        : constant String :=
                         Get_Active_Text (Vsearch.Pattern_Combo);
      Replace_Text   : constant String :=
                         Get_Active_Text (Vsearch.Replace_Combo);
      Whole_Word     : constant Boolean :=
                         Get_Active (Vsearch.Whole_Word_Toggle);
      Case_Sensitive : constant Boolean :=
                         Get_Active (Vsearch.Case_Toggle);
      Kind           : constant GPS.Search.Search_Kind :=
                         (if Get_Active (Vsearch.Regexp_Toggle) then
                             Regexp
                          else
                             Full_Text);
      Ctxt : Root_Search_Context_Access;
   begin
      if Data.Factory /= null and then Pattern /= "" then
         Ctxt := Data.Factory
           (Vsearch.Kernel,
            All_Occurrences,
            Vsearch.Selector);
      end if;

      if Ctxt = null then
         Insert (Vsearch.Kernel, -"Invalid search context specified");
         return null;
      end if;

      Ctxt.Set_Pattern
        (Pattern        => Pattern,
         Case_Sensitive => Case_Sensitive,
         Whole_Word     => Whole_Word,
         Kind           => Kind);
      Reset (Ctxt, Vsearch.Kernel);

      --  Update the contents of the combo boxes
      Add_To_History_And_Combo
        (Vsearch, Pattern,
         Whole_Word     => Whole_Word,
         Case_Sensitive => Case_Sensitive,
         Regexp         => Kind = Regexp);

      --  It sometimes happens that another entry is selected, for some
      --  reason. This also resets the options to the unwanted selection,
      --  so we also need to override them.
      Set_Active_Text (Vsearch.Pattern_Combo, Pattern);
      Vsearch.Case_Toggle.Set_Active (Case_Sensitive);
      Vsearch.Whole_Word_Toggle.Set_Active (Whole_Word);
      Vsearch.Regexp_Toggle.Set_Active (Kind = Regexp);

      Add_Unique_Combo_Entry
        (Vsearch.Replace_Combo, Replace_Text, Prepend => True);
      Add_To_History
        (Get_History (Vsearch.Kernel).all, Replace_Hist_Key, Replace_Text);
      Set_Active_Text (Vsearch.Replace_Combo, Replace_Text);

      return Ctxt;
   end Create_Context;

   -------------------------------
   -- Reset_Interactive_Context --
   -------------------------------

   procedure Reset_Interactive_Context
     (Vsearch : not null access Vsearch_Record'Class)
   is
   begin
      Free (Vsearch.Interactive_Context);

      --  Disable the replace buttons, since we haven't made sure the current
      --  position matches the pattern
      Vsearch.Replace_Button.Set_Sensitive (False);
      Vsearch.Replace_Search_Button.Set_Sensitive (False);
   end Reset_Interactive_Context;

   ---------------------
   -- Internal_Search --
   ---------------------

   procedure Internal_Search
     (Vsearch         : Vsearch_Access;
      All_Occurrences : Boolean := False;
      Replace         : Boolean := False)
   is
      Data     : constant Search_Module_Data :=
                   Find_Module
                     (Vsearch.Kernel, Get_Active_Id (Vsearch.Context_Combo));
      Toplevel : Gtk_Widget;
      Found    : Boolean;
      Has_Next : Boolean;
      Dummy    : Message_Dialog_Buttons;
      Ctxt     : Root_Search_Context_Access;

      Pattern  : constant String := Get_Active_Text (Vsearch.Pattern_Combo);
      C        : access Search_Command;
      Search_Category : constant String :=
        -"Search for: " & Vsearch.Pattern_Combo.Get_Active_Text;
   begin
      if All_Occurrences then
         --  If there is already a search going on for this category, do not
         --  launch a new one.
         if Has_Queue (Vsearch.Kernel, Search_Category) then
            return;
         end if;

         Vsearch.Find_Next := False;
         Ctxt := Create_Context (Vsearch, All_Occurrences);

      else
         --  Reuse the current context if there is one (to continue from where
         --  we were)

         if Vsearch.Interactive_Context = null then
            Reset_Interactive_Context (Vsearch);
            Ctxt := Create_Context (Vsearch, All_Occurrences);
            Vsearch.Interactive_Context := Ctxt;
         else
            Ctxt := Vsearch.Interactive_Context;
         end if;
      end if;

      if Ctxt /= null then
         if All_Occurrences then
            C := new Search_Command'
              (Interactive_Command with
               Select_Editor_On_Match => Select_On_Match.Get_Pref,
               Kernel            => Vsearch.Kernel,
               Search_Backward   => False,
               Context           => Ctxt,
               Context_Is_Owned  => True,  --  command will free context
               Found             => False);
            Launch_Background_Command
              (Vsearch.Kernel, C, True, True, Search_Category);

         else
            Search
              (Ctxt,
               Vsearch.Kernel,
               Search_Backward => False,
               Give_Focus      => Select_On_Match.Get_Pref,
               Found           => Found,
               Continue        => Has_Next);

            Vsearch.Replace_Button.Set_Sensitive
              (Found and then (Data.Mask and Supports_Replace) /= 0);
            Vsearch.Replace_Search_Button.Set_Sensitive
              (Found and then (Data.Mask and Supports_Replace) /= 0);

            --  Give a visual feedback that the search is terminated.
            if not Found
              and then not Has_Next
              and then not Get_End_Notif_Done (Ctxt.all)
            then
               Stop_Macro_Action_Hook.Run (Vsearch.Kernel);

               Toplevel := Vsearch.Get_Toplevel;
               if Gtk_Widget (Vsearch) = Toplevel then
                  Toplevel := Gtk_Widget (Vsearch.Kernel.Get_Main_Window);
               end if;

               Dummy := Message_Dialog
                 (Msg     => (-"No occurrences of '") & Pattern &
                  (-"' found in") & ASCII.LF
                  & Ctxt.Context_Look_In,
                  Title   => -"Search",
                  Buttons => Button_OK,
                  Parent  => Gtk_Window (Toplevel));
               Ctxt.Set_End_Notif_Done (True);
            end if;

            --  We keep the "Next" mode until a new context is created by
            --  the user, so that even after reaching the end of the search,
            --  we can restart from the beginning simply by pressing Ctrl-N
            Set_First_Next_Mode (Vsearch, Find_Next => True);
         end if;
      end if;

      --  If the dialog is not docked and the option to auto-close the dialog
      --  is set, close the dialog.

      if not Replace
        and then Vsearch.Get_Realized
        and then Is_Floating (Search_Views.Child_From_View (Vsearch))
        and then Close_On_Match.Get_Pref
      then
         Search_Views.Close (Vsearch.Kernel);
      end if;
   end Internal_Search;

   ---------------
   -- On_Search --
   ---------------

   procedure On_Search (Object : access Gtk_Widget_Record'Class) is
   begin
      Internal_Search (Vsearch_Access (Object));
   end On_Search;

   ------------------------
   -- On_Search_Previous --
   ------------------------

   procedure On_Search_Previous (Object : access Gtk_Widget_Record'Class) is
      Vsearch        : constant Vsearch_Access := Vsearch_Access (Object);
      All_Occurences : constant Boolean := False;
      Found          : Boolean;
      Has_Next       : Boolean;
      Ctxt           : Root_Search_Context_Access;

   begin
      Reset_Interactive_Context (Vsearch);
      Ctxt := Create_Context (Vsearch, All_Occurences);

      if Ctxt /= null then
         Vsearch.Interactive_Context := Ctxt;  --  owned by vsearch

         Search
           (Ctxt,
            Vsearch.Kernel,
            Search_Backward => True,
            Give_Focus      => Select_On_Match.Get_Pref,
            Found           => Found,
            Continue        => Has_Next);

         if not Found then
            Stop_Macro_Action_Hook.Run (Vsearch.Kernel);
         end if;

         Vsearch.Replace_Search_Button.Set_Sensitive (Found);
         Vsearch.Replace_Button.Set_Sensitive (Found);
         Set_First_Next_Mode (Vsearch, Find_Next => True);
      end if;
   end On_Search_Previous;

   -------------------
   -- On_Search_All --
   -------------------

   procedure On_Search_All (Object : access Gtk_Widget_Record'Class) is
   begin
      Internal_Search (Vsearch_Access (Object), True);
   end On_Search_All;

   ----------------
   -- On_Replace --
   ----------------

   procedure On_Replace (Object : access Gtk_Widget_Record'Class) is
      C        : access Replace_Command;
      Result   : Command_Return_Type with Unreferenced;
   begin
      C := Create_Replace (Vsearch_Access (Object), All_Occurrences => False);
      if C /= null then
         Result := C.Execute;
         Unref (Command_Access (C));
      end if;
   end On_Replace;

   -----------------------
   -- On_Replace_Search --
   -----------------------

   procedure On_Replace_Search (Object : access Gtk_Widget_Record'Class) is
   begin
      On_Replace (Object);
      On_Search (Object);
   end On_Replace_Search;

   --------------------
   -- On_Replace_All --
   --------------------

   procedure On_Replace_All (Object : access Gtk_Widget_Record'Class) is
      Vsearch     : constant Vsearch_Access := Vsearch_Access (Object);
      Has_Next    : Boolean;
      pragma Unreferenced (Has_Next);

      Dialog : constant Gtk_Dialog := Create_Gtk_Dialog
        (Msg      => (-"You are about to replace all occurrences of """)
         & Get_Active_Text (Vsearch.Pattern_Combo) & """."
         & ASCII.LF & (-"Continue?"),
         Dialog_Type => Warning,
         Title       => -"Replacing all occurrences",
         Parent      => Gtk_Window (Get_Toplevel (Vsearch)));

      Dummy       : Gtk_Widget;
      Do_Not_Ask  : Gtk_Check_Button;
      Box         : Gtk_Hbox;
      Response    : Gtk_Response_Type;

   begin
      if Ask_Confirmation_For_Replace_All.Get_Pref then
         Gtk_New (Do_Not_Ask, -"Do not ask this question again");
         Gtk_New_Hbox (Box);
         Pack_Start (Get_Content_Area (Dialog), Box, True, True, 3);
         Pack_Start (Box, Do_Not_Ask, True, False, 3);

         Dummy := Add_Button
           (Dialog,
            Text => "Yes",
            Response_Id => Gtk_Response_Yes);

         Dummy := Add_Button
           (Dialog,
            Text => "No",
            Response_Id => Gtk_Response_No);

         Show_All (Dialog);
         Response := Run (Dialog);

         if Get_Active (Do_Not_Ask) then
            Set_Pref
              (Ask_Confirmation_For_Replace_All, Vsearch.Kernel, False);
         end if;

         Destroy (Dialog);

         if Response /= Gtk_Response_Yes then
            return;
         end if;
      end if;

      Launch_Background_Command
        (Vsearch.Kernel, Create_Replace (Vsearch, All_Occurrences => True),
         True, True, -"Search and replace");
   end On_Replace_All;

   --------------------
   -- Create_Replace --
   --------------------

   function Create_Replace
     (Vsearch         : not null access Vsearch_Record'Class;
      All_Occurrences : Boolean)
     return access Replace_Command'Class
   is
      Ctxt : Root_Search_Context_Access;
   begin
      if All_Occurrences then
         --  Create a new context
         Ctxt := Create_Context (Vsearch, All_Occurrences => All_Occurrences);

      else
         --  Reuse the context we already have, since we need to know the
         --  location of the last search

         Ctxt := Vsearch.Interactive_Context;
         Vsearch.Replace_Button.Set_Sensitive (False);
         Vsearch.Replace_Search_Button.Set_Sensitive (False);
      end if;

      if Ctxt = null then
         return null;
      end if;

      return new Replace_Command'
        (Interactive_Command with
         Search_Backward        => False,
         Context                => Ctxt,
         Context_Is_Owned       => All_Occurrences,  --  command will free ctxt
         Kernel                 => Vsearch.Kernel,
         Select_Editor_On_Match => Select_On_Match.Get_Pref,
         Found                  => False,
         Replace_With           =>
            new String'(Get_Active_Text (Vsearch.Replace_Combo)));
   end Create_Replace;

   ------------------------------
   -- On_Context_Entry_Changed --
   ------------------------------

   procedure On_Context_Combo_Changed
     (Object : access Gtk_Widget_Record'Class)
   is
      use Widget_List;

      Vsearch : constant Vsearch_Access := Vsearch_Access (Object);
      Data    : constant Search_Module_Data :=
                  Find_Module
                    (Vsearch.Kernel, Get_Active_Id (Vsearch.Context_Combo));
      Replace : Boolean;
      Child   : MDI_Child;

   begin
      if Data /= No_Search then
         Set_Last_Of_Module (Vsearch.Kernel, Data);
         Replace := (Data.Mask and Supports_Replace) /= 0;
         Set_Sensitive (Vsearch.Replace_Label, Replace);
         Set_Sensitive (Vsearch.Replace_Combo, Replace);
         Set_Sensitive (Vsearch.Replace_All_Button, Replace);

         if (Data.Mask and All_Occurrences) = 0 then
            Set_Sensitive (Vsearch.Replace_All_Button, False);
            Set_Sensitive (Vsearch.Search_All_Button, False);
         else
            Set_Sensitive (Vsearch.Search_All_Button, True);
         end if;

         if (Data.Mask and Case_Sensitive) = 0 then
            Set_Active (Vsearch.Case_Toggle, False);
         end if;

         if (Data.Mask and Whole_Word) = 0 then
            Set_Active (Vsearch.Whole_Word_Toggle, False);
         end if;

         Set_Sensitive
           (Vsearch.Case_Toggle, (Data.Mask and Case_Sensitive) /= 0);
         Set_Sensitive
           (Vsearch.Whole_Word_Toggle, (Data.Mask and Whole_Word) /= 0);
         Set_Sensitive (Vsearch.Search_Previous_Button,
                        (Data.Mask and Search_Backward) /= 0);

         --  We remove the scope selector widgets, but there is still one
         --  reference hold by the module, so they don't get destroyed.
         if Vsearch.Scope_Selector_Combo /= null then
            Vsearch.Scope_Selector_Box.Remove
              (Vsearch.Scope_Separator_Label);
            Vsearch.Scope_Selector_Box.Remove
              (Vsearch.Scope_Selector_Combo);
         end if;

         if Vsearch.Scope_Selector_Optional /= null then
            Vsearch.Scope_Optional_Box.Remove
              (Vsearch.Scope_Selector_Optional);
         end if;

         Vsearch.Selector := null;
         Vsearch.Scope_Selector_Combo := null;
         Vsearch.Scope_Selector_Optional := null;

         if Data.Selector /= null then
            Vsearch.Selector := Data.Selector;
            Vsearch.Scope_Selector_Combo :=
              Data.Selector.Get_Scope_Combo;
            Vsearch.Scope_Selector_Optional :=
              Data.Selector.Get_Optional_Widget;

            Gtk_New (Vsearch.Scope_Separator_Label, "In");
            Vsearch.Scope_Selector_Box.Pack_End
              (Vsearch.Scope_Separator_Label,
               Expand  => False,
               Padding => H_Padding);

            Vsearch.Scope_Selector_Box.Pack_End
              (Vsearch.Scope_Selector_Combo,
               Expand => True,
               Fill   => True);

            if Vsearch.Scope_Selector_Optional /= null then
               Vsearch.Scope_Optional_Box.Pack_Start
                 (Vsearch.Scope_Selector_Optional,
                  Expand => True,
                  Fill   => True);
            end if;

            Show_All (Vsearch.Scope_Main_Box);
         end if;

         Child := Search_Views.Child_From_View (Vsearch);
         if Child /= null and then Is_Floating (Child) then
            --  Reset if any size was set previously
            Vsearch.Set_Size_Request (-1, -1);
            Vsearch.Queue_Resize;
         end if;
      end if;
   end On_Context_Combo_Changed;

   -------------------------
   -- Set_First_Next_Mode --
   -------------------------

   procedure Set_First_Next_Mode
     (Vsearch   : access Vsearch_Record'Class;
      Find_Next : Boolean)
   is
      Label : Gtk_Label;
      Align : Gtk_Alignment;
      Req   : Gtk_Requisition;

   begin
      Vsearch.Find_Next := Find_Next;

      if Find_Next then
         --  Make sure the Search_Next_Button only grows in size. This makes
         --  sure that a user won't click on "Find" and see the button shrink
         --  so that next time he clicks (without moving the mouse) is on
         --  "Replace".

         Size_Request (Vsearch.Search_Next_Button, Req);
         Set_Size_Request (Vsearch.Search_Next_Button, Req.Width, Req.Height);

         Remove (Vsearch.Search_Next_Button,
                 Get_Child (Vsearch.Search_Next_Button));

         Gtk_New_With_Mnemonic (Label, -"_Next");
         Gtk_New (Align, 0.5, 0.5, 0.0, 0.0);
         Add (Vsearch.Search_Next_Button, Align);
         Add (Align, Label);
         Show_All (Align);

         Vsearch_Module_Id.Search_Started := True;

         --  Always activate the "Next" button, so that we can still do
         --  selective replace. Otherwise, the button is greyed out when we
         --  have a replace string, and would stay as such.
         Set_Sensitive (Vsearch.Search_Next_Button, True);

      else
         --  Remove size constraints on Search_Next_Button.
         Set_Size_Request (Vsearch.Search_Next_Button, -1, -1);
         Remove (Vsearch.Search_Next_Button,
                 Get_Child (Vsearch.Search_Next_Button));

         Gtk_New_With_Mnemonic (Label, -"_Find");
         Gtk_New (Align, 0.5, 0.5, 0.0, 0.0);
         Add (Vsearch.Search_Next_Button, Align);
         Add (Align, Label);
         Show_All (Align);

         Vsearch_Module_Id.Search_Started := False;
      end if;
   end Set_First_Next_Mode;

   -------------
   -- Execute --
   -------------

   overriding procedure Execute
     (Self   : Set_First_Next_Mode_Cb;
      Kernel : not null access Kernel_Handle_Record'Class)
   is
      pragma Unreferenced (Self);
      View : constant Vsearch_Access := Search_Views.Retrieve_View (Kernel);
   begin
      --  We might be in the process of destroying GPS (for instance, the
      --  current search context detects that the current MDI_Child was
      --  destroyed, and resets the context).
      if View /= null then
         Set_First_Next_Mode (View, Find_Next => False);
         Reset_Interactive_Context (View);
      end if;
   end Execute;

   -------------
   -- Execute --
   -------------

   overriding procedure Execute
     (Self   : On_Project_View_Changed;
      Kernel : not null access Kernel_Handle_Record'Class)
   is
      pragma Unreferenced (Self);
   begin
      Reset_Search (null, Kernel_Handle (Kernel));
   end Execute;

   ---------------
   -- Key_Press --
   ---------------

   function Key_Press
     (Vsearch : access Gtk_Widget_Record'Class;
      Event   : Gdk_Event) return Boolean
   is
      Ext : constant Vsearch_Access := Vsearch_Access (Vsearch);
   begin
      if Get_Key_Val (Event) = GDK_Return
        or else Get_Key_Val (Event) = GDK_KP_Enter
      then
         if Is_Sensitive (Ext.Search_Next_Button) then
            Grab_Focus (Ext.Search_Next_Button);
            On_Search (Vsearch);
         else
            Grab_Focus (Ext.Replace_Search_Button);
            On_Replace (Ext);
         end if;
         return True;
      end if;
      return False;
   end Key_Press;

   -----------------------
   -- Key_Press_Replace --
   -----------------------

   function Key_Press_Replace
     (Vsearch : access Gtk_Widget_Record'Class;
      Event   : Gdk_Event) return Boolean
   is
      Ext : constant Vsearch_Access := Vsearch_Access (Vsearch);
   begin
      if Get_Key_Val (Event) = GDK_Return
        or else Get_Key_Val (Event) = GDK_KP_Enter
      then
         Grab_Focus (Ext.Replace_Search_Button);
         On_Replace_Search (Ext);
         return True;
      end if;

      return False;

   exception
      when E : others =>
         Trace (Me, E);
         return False;
   end Key_Press_Replace;

   -----------------------
   -- Selection_Changed --
   -----------------------

   procedure Selection_Changed
     (Vsearch : access Gtk_Widget_Record'Class)
   is
      use Widget_List;
      Search : constant Vsearch_Access := Vsearch_Access (Vsearch);
      Iter           : Gtk_Tree_Iter;
      Case_Sensitive : Boolean;
      Is_Regexp      : Boolean;
      Whole_Word     : Boolean;

   begin
      if Get_Active_Iter (Search.Pattern_Combo) /= Null_Iter then
         Iter := Get_Active_Iter (Search.Pattern_Combo);
         Case_Sensitive := Get_Boolean
           (Search.Pattern_Combo.Get_Model, Iter, Column_Case_Sensitive);
         Is_Regexp := Get_Boolean
           (Search.Pattern_Combo.Get_Model, Iter, Column_Is_Regexp);
         Whole_Word := Get_Boolean
           (Search.Pattern_Combo.Get_Model, Iter, Column_Whole_Word);

         Set_Active (Search.Case_Toggle, Case_Sensitive);
         Set_Active (Search.Regexp_Toggle, Is_Regexp);
         Set_Active (Search.Whole_Word_Toggle, Whole_Word);
      end if;

   exception
      when Gtkada.Types.Data_Error =>
         null;
   end Selection_Changed;

   -------------
   -- Execute --
   -------------

   overriding procedure Execute
     (Self   : New_Predefined_Regexp;
      Kernel : not null access Kernel_Handle_Record'Class)
   is
      pragma Unreferenced (Self);
      Search : constant Vsearch_Access := Search_Views.Retrieve_View (Kernel);
      Item    : Gtk_Tree_Iter;
      List    : Gtk_List_Store;
      Casing     : constant Boolean := Get_Active (Search.Case_Toggle);
      Whole_Word : constant Boolean := Get_Active (Search.Whole_Word_Toggle);
      Regexp     : constant Boolean := Get_Active (Search.Regexp_Toggle);

   begin
      for R of Vsearch_Module_Id.Search_Regexps.all loop
         Item := Add_Unique_Combo_Entry (Search.Pattern_Combo, R.Name.all);
         List := -Get_Model (Search.Pattern_Combo);
         List.Set (Item, Column_Pattern,        R.Regexp.all);
         List.Set (Item, Column_Case_Sensitive, R.Case_Sensitive);
         List.Set (Item, Column_Is_Regexp,      R.Is_Regexp);
         List.Set (Item, Column_Whole_Word,     False);
      end loop;

      --  Restore the options as before (they might have changed depending
      --  on the last predefined regexp we inserted)

      Set_Active (Search.Case_Toggle, Casing);
      Set_Active (Search.Whole_Word_Toggle, Whole_Word);
      Set_Active (Search.Regexp_Toggle, Regexp);
   end Execute;

   ---------------------------
   -- Refresh_Context_Combo --
   ---------------------------

   procedure Refresh_Context_Combo
     (Kernel : access Kernel_Handle_Record'Class)
   is
      Vsearch : constant Vsearch_Access := Search_Views.Retrieve_View (Kernel);
      Num : Positive := 1;
      Store : constant Gtk_List_Store :=
        Gtk_List_Store'(-Vsearch.Context_Combo.Get_Model);
      Id_Col : constant Gint := Vsearch.Context_Combo.Get_Id_Column;
      Iter  : Gtk_Tree_Iter;
      Found : Boolean;
   begin
      loop
         declare
            Data : constant Search_Module_Data :=
              Get_Nth_Search_Module (Kernel, Num);
         begin
            exit when Data = No_Search;

            Found := False;
            Iter := Store.Get_Iter_First;
            while Iter /= Null_Iter loop
               --  The id is the un-substituted label
               if Get_String (Store, Iter, Id_Col) = Data.Label.all then
                  --  Update the text, after substituting macros.
                  Store.Set
                    (Iter, 0, Substitute_Label (Kernel, Data.Label.all));
                  Found := True;
                  exit;
               end if;
               Store.Next (Iter);
            end loop;

            if not Found then
               Vsearch.Context_Combo.Append
                 (Id   => Data.Label.all,
                  Text => Substitute_Label (Kernel, Data.Label.all));
            end if;

            Num := Num + 1;
         end;
      end loop;
   end Refresh_Context_Combo;

   -------------
   -- Execute --
   -------------

   overriding procedure Execute
     (Self   : Search_Functions_Changed;
      Kernel : not null access Kernel_Handle_Record'Class)
   is
      pragma Unreferenced (Self);
   begin
      Refresh_Context_Combo (Kernel);
   end Execute;

   -----------------------
   -- On_Button_Release --
   -----------------------

   function On_Button_Release
     (Self  : access Gtk_Widget_Record'Class;
      Event : Gdk_Event_Button) return Boolean
   is
      E : constant Gtk_Entry := Gtk_Entry (Self);
   begin
      if not Vsearch_Module_Id.Has_Focus_On_Click and Event.Button = 1 then
         E.Select_Region (0, -1);
      end if;

      return False;
   end On_Button_Release;

   ---------------------
   -- On_Button_Press --
   ---------------------

   function On_Button_Press
     (Self  : access Gtk_Widget_Record'Class;
      Event : Gdk_Event_Button) return Boolean
   is
      pragma Unreferenced (Event);
      E : constant Gtk_Entry := Gtk_Entry (Self);
   begin
      Vsearch_Module_Id.Has_Focus_On_Click := E.Is_Focus;
      return False;
   end On_Button_Press;

   ------------------------
   -- On_Vsearch_Destroy --
   ------------------------

   procedure On_Vsearch_Destroy (Self : access Gtk_Widget_Record'Class) is
      Vsearch : constant Vsearch_Access := Vsearch_Access (Self);
   begin
      --  The widgets in Context_Specific have a longer lifecycle than the
      --  dialog itself: make sure here that they are not destroyed when the
      --  dialog is destroyed.
      if Vsearch.Scope_Selector_Combo /= null then
         Vsearch.Scope_Selector_Box.Remove
           (Vsearch.Scope_Selector_Combo);
      end if;

      if Vsearch.Scope_Selector_Optional /= null then
         Vsearch.Scope_Optional_Box.Remove
           (Vsearch.Scope_Selector_Optional);
      end if;

      Reset_Interactive_Context (Vsearch);
   end On_Vsearch_Destroy;

   ----------------
   -- Initialize --
   ----------------

   function Initialize
     (Self : access Vsearch_Record'Class) return Gtk_Widget
   is

      procedure Disable_Button_Focus (Combo_Box : Gtk_Combo_Box);
      --  Disable focus on internal button in given Combo_Box

      procedure Set_Mode_From_History;
      --  If the vsearch mode is Unknown, set it from its corresponding history
      --  key.

      --------------------------
      -- Disable_Button_Focus --
      --------------------------

      procedure Disable_Button_Focus (Combo_Box : Gtk_Combo_Box) is
         Focus_Chain : Gtk.Widget.Widget_List.Glist;
      begin
         --  Create single element list that contains only text entry
         Gtk.Widget.Widget_List.Append (Focus_Chain, Combo_Box.Get_Child);
         --  Set it as focus chain
         Combo_Box.Set_Focus_Chain (Focus_Chain);
      end Disable_Button_Focus;

      ---------------------------
      -- Set_Mode_From_History --
      ---------------------------

      procedure Set_Mode_From_History is
         Last_Mode : constant String_List_Access :=
                       Get_History
                         (Get_History (Self.Kernel).all, Mode_Hist_Key);
      begin
         if Last_Mode /= null and then Self.Mode = Unknown then
            Self.Set_Vsearch_Mode
              (Mode => Vsearch_Mode'Value (Last_Mode (Last_Mode'Last).all));
         end if;
      end Set_Mode_From_History;

      Pane             : Gtk_Paned;
      Main_Vbox        : Gtk_Vbox;
      Button_Box       : Gtk_Button_Box;
      Row              : Gtk_Hbox;
      Layout           : Gtk_Cell_Layout;
      Renderer         : Gtk_Cell_Renderer_Text;
      Value            : String_List_Access;
      Model            : Gtk_List_Store;
      Label            : Gtk_Label;
      Label_Size_Group : Gtk_Size_Group;
   begin
      Gtk.Box.Initialize_Vbox (Self);

      Gtk_New (Self.View);
      Self.View.Set_Shadow_Type (Shadow_None);
      Self.Add (Self.View);

      Gtk_New_Hpaned (Pane);
      Self.View.Add (Pane);

      Gtk_New_Vbox (Main_Vbox, False, 0);
      Main_Vbox.Set_Border_Width (5);
      Pane.Pack1
        (Main_Vbox,
         Resize => True,
         Shrink => False);

      Gtk_New (Label_Size_Group);

      --  Find/Replace combo boxes

      Gtk_New_Hbox (Row, Homogeneous => False);
      Main_Vbox.Pack_Start (Row, Expand => False);

      Gtk_New (Label, -("Find"));
      Label_Size_Group.Add_Widget (Label);
      Label.Set_Alignment (0.0, 0.5);
      Row.Pack_Start (Label, Expand => False, Padding => H_Padding);

      Gtk.List_Store.Gtk_New
        (Model,
         (Guint (Column_Text)           => GType_String,
          Guint (Column_Pattern)        => GType_String,
          Guint (Column_Case_Sensitive) => GType_Boolean,
          Guint (Column_Is_Regexp)      => GType_Boolean,
          Guint (Column_Whole_Word)     => GType_Boolean));
      Gtk_New_With_Model_And_Entry (Self.Pattern_Combo, +Model);
      Self.Pattern_Combo.Set_Entry_Text_Column (Column_Pattern);
      Row.Pack_Start (Self.Pattern_Combo, Expand => True, Fill => True);
      Layout := +Self.Pattern_Combo;

      Self.Pattern_Combo.Get_Child.On_Button_Press_Event
        (On_Button_Press'Access, After => False);

      Self.Pattern_Combo.Get_Child.On_Button_Release_Event
        (On_Button_Release'Access, After => False);

      Disable_Button_Focus (Self.Pattern_Combo);

      Gtk_New (Renderer);
      Gtk.Cell_Layout.Clear (Layout);
      Gtk.Cell_Layout.Pack_Start (Layout, Renderer, True);
      Gtk.Cell_Layout.Add_Attribute (Layout, Renderer, "text", Column_Text);
      Set_Tooltip_Text (Self.Pattern_Combo,
                        -"The searched word or pattern");

      Gtk_New_Hbox (Row, Homogeneous => False);
      Main_Vbox.Pack_Start (Row, Expand => False);

      Gtk_New (Self.Replace_Label, -("Replace"));
      Self.Replace_Label.Set_No_Show_All (True);
      Label_Size_Group.Add_Widget (Self.Replace_Label);
      Self.Replace_Label.Set_Alignment (0.0, 0.5);
      Row.Pack_Start
        (Self.Replace_Label,
         Expand  => False,
         Padding => H_Padding);

      Gtk.List_Store.Gtk_New (Model, (0 .. 0 => GType_String));

      Gtk_New_With_Model_And_Entry (Self.Replace_Combo, +Model);
      Self.Replace_Combo.Set_No_Show_All (True);
      Self.Replace_Combo.Set_Entry_Text_Column (0);
      Row.Pack_Start (Self.Replace_Combo, Expand => True, Fill => True);
      Self.Replace_Combo.Set_Tooltip_Text
        (-("The text that will replace each match. Next special patterns are" &
           " recognized in regexp mode:" & ASCII.LF &
           " * \0 - refers to the complete matched string" & ASCII.LF &
           " * \1..\9 - refer to the corresponding matching subexpression" &
           ASCII.LF &
           " * \i or \i(start,step) - refers to the sequentially " &
           "increasing number"));

      Disable_Button_Focus (Self.Replace_Combo);

      Self.Replace_Combo.Get_Child.On_Button_Press_Event
        (On_Button_Press'Access, After => False);

      Self.Replace_Combo.Get_Child.On_Button_Release_Event
        (On_Button_Release'Access, After => False);

      --  Context specific search

      Gtk_New_Vbox (Self.Scope_Main_Box, Homogeneous => False);
      Main_Vbox.Pack_Start (Self.Scope_Main_Box, Expand => False);

      Gtk_New_Hbox (Self.Scope_Selector_Box, Homogeneous => False);
      Self.Scope_Main_Box.Pack_Start
        (Self.Scope_Selector_Box,
         Expand => False);

      Gtk_New (Label, -("Where"));
      Label_Size_Group.Add_Widget (Label);
      Label.Set_Alignment (0.0, 0.5);
      Self.Scope_Selector_Box.Pack_Start
        (Label,
         Expand  => False,
         Padding => H_Padding);

      Gtk_New (Self.Context_Combo);
      Self.Context_Combo.Set_Tooltip_Text (-"The context of the search");
      Self.Scope_Selector_Box.Pack_End
        (Self.Context_Combo,
         Expand => True,
         Fill   => True);
      Widget_Callback.Object_Connect
        (Self.Context_Combo, Gtk.Combo_Box.Signal_Changed,
         On_Context_Combo_Changed'Access, Self);
      Self.Context_Combo.Set_Name ("search scope combo");

      Gtk_New_Vbox (Self.Scope_Optional_Box, Homogeneous => False);
      Self.Scope_Main_Box.Pack_Start
        (Self.Scope_Optional_Box,
         Expand => True,
         Fill   => True);

      --  The buttons

      Gtk_New (Button_Box, Orientation => Orientation_Vertical);
      Button_Box.Set_Layout (Buttonbox_Start);
      Pane.Pack2 (Button_Box,
                  Resize => False,
                  Shrink => False);

      Gtk_New_With_Mnemonic (Self.Search_Next_Button, -"_Find");
      Set_First_Next_Mode (Self, Find_Next => False);
      Button_Box.Pack_Start (Self.Search_Next_Button, Expand => False);
      Self.Search_Next_Button.Set_Tooltip_Text (-"Search next occurrence");
      Widget_Callback.Object_Connect
        (Self.Search_Next_Button, Signal_Clicked,
         On_Search'Access, Self);

      Gtk_New_With_Mnemonic (Self.Search_Previous_Button, -"_Previous");
      Self.Search_Previous_Button.Set_No_Show_All (True);
      Button_Box.Pack_Start
        (Self.Search_Previous_Button,
         Expand => False);
      Self.Search_Previous_Button.Set_Tooltip_Text
        (-"Search previous occurrence");
      Widget_Callback.Object_Connect
        (Self.Search_Previous_Button, Signal_Clicked,
         On_Search_Previous'Access, Self);

      Gtk_New_With_Mnemonic (Self.Search_All_Button, -"Find All");
      Self.Search_All_Button.Set_No_Show_All (True);
      Button_Box.Pack_Start (Self.Search_All_Button, Expand => False);
      Self.Search_All_Button.Set_Tooltip_Text (-"Find all occurences");
      Widget_Callback.Object_Connect
        (Self.Search_All_Button, Signal_Clicked,
         On_Search_All'Access, Self);

      Gtk_New (Self.Replace_Button, -"Replace");
      Self.Replace_Button.Set_No_Show_All (True);
      Button_Box.Pack_Start (Self.Replace_Button, Expand => False);
      Self.Replace_Button.Set_Tooltip_Text (-"Replace next occurrence");
      Widget_Callback.Object_Connect
        (Self.Replace_Button, Signal_Clicked,
         On_Replace'Access, Self);
      Self.Replace_Button.Set_Sensitive (False);

      Gtk_New_With_Mnemonic (Self.Replace_Search_Button, -"Replace & Find");
      Self.Replace_Search_Button.Set_No_Show_All (True);
      Button_Box.Pack_Start
        (Self.Replace_Search_Button,
         Expand => False);
      Self.Replace_Search_Button.Set_Tooltip_Text
        (-"Replace, then find next occurrence");
      Widget_Callback.Object_Connect
        (Self.Replace_Search_Button, Signal_Clicked,
         On_Replace_Search'Access, Self);

      Gtk_New_With_Mnemonic (Self.Replace_All_Button, -"Replace All");
      Self.Replace_All_Button.Set_No_Show_All (True);
      Button_Box.Pack_Start (Self.Replace_All_Button, Expand => False);
      Self.Replace_All_Button.Set_Tooltip_Text
        (-"Replace all occurences");
      Widget_Callback.Object_Connect
        (Self.Replace_All_Button, Signal_Clicked,
         On_Replace_All'Access, Self);

      Self.On_Destroy (On_Vsearch_Destroy'Access);

      --  Any change to the fields resets the search mode
      Return_Callback.Object_Connect
        (Self.Pattern_Combo.Get_Child, Signal_Key_Press_Event,
         Return_Callback.To_Marshaller (Key_Press'Access), Self);
      Return_Callback.Object_Connect
        (Self.Replace_Combo.Get_Child, Signal_Key_Press_Event,
         Return_Callback.To_Marshaller (Key_Press_Replace'Access), Self);
      Kernel_Callback.Connect
        (Self.Pattern_Combo, Gtk.Combo_Box.Signal_Changed,
         Reset_Search'Access, Self.Kernel);
      Kernel_Callback.Connect
        (Self.Context_Combo, Gtk.Combo_Box.Signal_Changed,
         Reset_Search'Access, Self.Kernel);

      --  Fill the replace combo first, so that the selection remains in
      --  the pattern combo
      Get_History
        (Get_History (Self.Kernel).all, Replace_Hist_Key, Self.Replace_Combo,
         Clear_Combo => False, Prepend => True);

      Value := Get_History (Get_History (Self.Kernel).all, Pattern_Hist_Key);

      if Value /= null then
         for V in Value'Range loop
            Add_History_To_Combo (Self, Value (V).all);
         end loop;

         Self.Pattern_Combo.Set_Active (0);
         Gtk_Entry (Self.Pattern_Combo.Get_Child).Select_Region (0, -1);
      else
         Set_Active_Text (Self.Pattern_Combo, "");
      end if;

      --  Create a key in the history to save the last used vsearch mode and
      --  retrieve it if it already exists.
      Create_New_Key_If_Necessary
        (Get_History (Self.Kernel).all,
         Key       => Mode_Hist_Key,
         Key_Type  => Strings);
      Set_Max_Length
        (Get_History (Self.Kernel).all,
         Num  => 1,
         Key  => Mode_Hist_Key);
      Set_Mode_From_History;

      Search_Reset_Hook.Add (new Set_First_Next_Mode_Cb);
      Search_Functions_Changed_Hook.Add (new Search_Functions_Changed);
      Search_Regexps_Changed_Hook.Add (new New_Predefined_Regexp);
      Project_View_Changed_Hook.Add (new On_Project_View_Changed);

      --  ??? Should be changed when prefs are changed
      Set_Font_And_Colors (Main_Vbox, Fixed_Font => False);

      return Self.Pattern_Combo.Get_Child;
   end Initialize;

   ----------------------
   -- Set_Vsearch_Mode --
   ----------------------

   procedure Set_Vsearch_Mode
     (Self : not null access Vsearch_Record'Class;
      Mode : Vsearch_Mode)
   is
      Show_Replace_Widgets : constant Boolean := Mode = Find_And_Replace;
   begin
      Self.Mode := Mode;
      Add_To_History
        (Self.Kernel,
         Key       => Mode_Hist_Key,
         New_Entry => Mode'Image);

      Self.Replace_Label.Set_Visible (Show_Replace_Widgets);
      Self.Replace_Combo.Set_Visible (Show_Replace_Widgets);
      Self.Replace_Button.Set_Visible (Show_Replace_Widgets);
      Self.Replace_All_Button.Set_Visible (Show_Replace_Widgets);
      Self.Replace_Search_Button.Set_Visible (Show_Replace_Widgets);
      Self.Search_Previous_Button.Set_Visible (not Show_Replace_Widgets);
      Self.Search_All_Button.Set_Visible (not Show_Replace_Widgets);
   end Set_Vsearch_Mode;

   ------------------
   -- Receive_Text --
   ------------------

   procedure Receive_Text
     (Clipboard : not null access Gtk_Clipboard_Record'Class;
      Text      : Glib.UTF8_String)
   is
      pragma Unreferenced (Clipboard);
      View : constant Vsearch_Access := Search_Views.Retrieve_View
        (Vsearch_Module_Id.Get_Kernel);
   begin
      if Text /= ""
        and then Text'Length < 128
      then
         Set_Active_Text (View.Pattern_Combo, Text);
      end if;
   end Receive_Text;

   --------------------
   -- Create_Toolbar --
   --------------------

   overriding procedure Create_Toolbar
     (View    : not null access Vsearch_Record;
      Toolbar : not null access Gtk.Toolbar.Gtk_Toolbar_Record'Class)
   is

   begin
      Gtk_New (View.Regexp_Toggle);
      View.Regexp_Toggle.Set_Icon_Name ("gps-regexp-symbolic");
      View.Regexp_Toggle.Set_Tooltip_Text
        (-"The pattern is a regular expression");
      Create_New_Boolean_Key_If_Necessary
        (Get_History (View.Kernel).all, "regexp_search", False);
      Associate
        (Get_History (View.Kernel).all, "regexp_search", View.Regexp_Toggle,
         Default => False);
      Kernel_Callback.Connect
        (View.Regexp_Toggle,
         Gtk.Toggle_Tool_Button.Signal_Toggled,
         Reset_Search'Access,
         View.Kernel);
      Toolbar.Insert (View.Regexp_Toggle);

      Gtk_New (View.Case_Toggle);
      View.Case_Toggle.Set_Icon_Name ("gps-case-sensitive-symbolic");
      View.Case_Toggle.Set_Tooltip_Text
        (-("Select this to differenciate upper from lower casing in search"
         & " results"));
      Create_New_Boolean_Key_If_Necessary
        (Get_History (View.Kernel).all, "case_sensitive_search", False);
      Associate
        (Get_History (View.Kernel).all, "case_sensitive_search",
         View.Case_Toggle, Default => False);
      Kernel_Callback.Connect
        (View.Case_Toggle,
         Gtk.Toggle_Tool_Button.Signal_Toggled,
         Reset_Search'Access,
         View.Kernel);
      Toolbar.Insert (View.Case_Toggle);

      Gtk_New (View.Whole_Word_Toggle);
      View.Whole_Word_Toggle.Set_Icon_Name ("gps-whole-word-symbolic");
      View.Whole_Word_Toggle.Set_Tooltip_Text
        (-("Select this if the pattern should only match a whole word, never"
         & " part of a word"));
      Create_New_Boolean_Key_If_Necessary
        (Get_History (View.Kernel).all, "whole_word_search", False);
      Associate
        (Get_History (View.Kernel).all, "whole_word_search",
         View.Whole_Word_Toggle, Default => False);
      Kernel_Callback.Connect
        (View.Whole_Word_Toggle,
         Gtk.Toggle_Tool_Button.Signal_Toggled,
         Reset_Search'Access,
         View.Kernel);
      Toolbar.Insert (View.Whole_Word_Toggle);

      --  Include all the patterns that have been predefined so far, and make
      --  sure that new patterns will be automatically added.
      Widget_Callback.Object_Connect
        (View.Pattern_Combo, Gtk.Combo_Box.Signal_Changed,
         Selection_Changed'Access, View);
   end Create_Toolbar;

   -----------------
   -- Create_Menu --
   -----------------

   overriding procedure Create_Menu
     (View    : not null access Vsearch_Record;
      Menu    : not null access Gtk.Menu.Gtk_Menu_Record'Class) is
   begin
      Append_Menu
        (Menu,
         Kernel => View.Kernel,
         Pref   => Close_On_Match);
      Append_Menu
        (Menu,
         Kernel => View.Kernel,
         Pref   => Select_On_Match);
   end Create_Menu;

   ---------------
   -- On_Create --
   ---------------

   overriding procedure On_Create
     (Self  : not null access Vsearch_Record;
      Child : not null access GPS_MDI_Child_Record'Class)
   is
      P  : aliased Search_Functions_Changed;
      P2 : aliased New_Predefined_Regexp;
   begin
      P.Execute (Self.Kernel);
      P2.Execute (Self.Kernel);

      Widget_Callback.Connect (Child, Signal_Float_Child, On_Float'Access);
      Widget_Callback.Connect (Child, Signal_Unfloat_Child, On_Float'Access);
      On_Float (Child);  --  hide or show the buttons
   end On_Create;

   ---------------------------
   -- Get_Or_Create_Vsearch --
   ---------------------------

   function Get_Or_Create_Vsearch
     (Kernel        : access Kernel_Handle_Record'Class;
      Raise_Widget  : Boolean := False;
      Reset_Entries : Boolean := False;
      Context       : GNAT.Strings.String_Access := null;
      Mode          : Vsearch_Mode := Find_Only) return Vsearch_Access
   is
      --  We must create the search dialog only after we have found the current
      --  context, otherwise it would return the context of the search widget
      --  itself
      Selected   : constant Selection_Context := Get_Current_Context (Kernel);
      Module     : constant Module_ID := Module_ID (Get_Creator (Selected));
      W          : constant Gtk_Widget := Get_Current_Focus_Widget (Kernel);
      Buffer     : Gtk_Text_Buffer;
      First_Iter : Gtk_Text_Iter;
      Last_Iter  : Gtk_Text_Iter;

      Has_Selection : Boolean := False;
      --  If W has selecion saved in First_Iter, Last_Iter
      Has_Multiline_Selection : Boolean := False;
      --  If W has multiline selecion saved in First_Iter, Last_Iter

      View     : Vsearch_Access;
      Dummy    : Boolean;
      Default_Pattern         : GNAT.Strings.String_Access := null;

   begin
      declare
         Start, Stop : Gint;
         Success : Boolean := False;
      begin
         if W /= null
           and then Is_A (W.Get_Type, Gtk.Editable.Get_Type)
         then
            Get_Selection_Bounds (+W, Start, Stop, Success);

            if Success and then Start /= Stop then
               Default_Pattern := new String'(Get_Chars (+W, Start, Stop));
            end if;
         elsif W /= null and then W.all in Gtk_Text_View_Record'Class then
            Buffer := Get_Buffer (Gtk_Text_View (W));
            Get_Selection_Bounds
              (Buffer, First_Iter, Last_Iter, Has_Selection);

            if Has_Selection then
               if Get_Line (First_Iter) = Get_Line (Last_Iter) then
                  Default_Pattern := new String'
                    (Get_Slice (Buffer, First_Iter, Last_Iter));

                  Select_Range (Buffer, First_Iter, First_Iter);
               else
                  Has_Multiline_Selection := True;
               end if;
            end if;
         end if;

         if Default_Pattern /= null
           and then
             (Default_Pattern'Length >= 128
              or else Index (Default_Pattern.all, (1 => ASCII.LF)) /= 0)
         then
            --  In this case, the selection is not suitable for being used by
            --  the search widget

            Free (Default_Pattern);
         end if;
      end;

      View := Search_Views.Get_Or_Create_View (Kernel, Focus => Raise_Widget);

      --  Automatically fill the pattern text entry with the selection, if
      --  there is one which does not contain multiple lines.
      --  We also set the "Replace" in this case, since users will generally
      --  want to make a minor modification, rather than reuse the previous
      --  replacement text (which is still accessible through the combo).

      if Default_Pattern /= null then
         Set_Active_Text (View.Pattern_Combo, Default_Pattern.all);
         Set_Active_Text (View.Replace_Combo, Default_Pattern.all);
         Free (Default_Pattern);
      else
         Request_Text
           (Gtk.Clipboard.Get (Selection_Primary),
            Receive_Text'Access);
      end if;

      if Has_Selection then
         --  Restore multiline selection
         if Has_Multiline_Selection then
            Select_Range (Buffer, First_Iter, Last_Iter);
         end if;

         View.Selection_From := Buffer.Create_Mark
           (Mark_Name    => "search_from",
            Where        => First_Iter,
            Left_Gravity => True);

         View.Selection_To := Buffer.Create_Mark
           (Mark_Name    => "search_to",
            Where        => Last_Iter,
            Left_Gravity => False);
      end if;

      Set_Selected_Project (Kernel, Selected);

      if Reset_Entries then
         --  ??? Temporarily: reset the entry. The correct fix would be to
         --  separate the find and replace tabs, so that having a default
         --  entry in this combo doesn't look strange when the combo is
         --  insensitive.

         if Context = null then
            if Module /= null then
               declare
                  Search : constant Search_Module_Data :=
                    Search_Context_From_Module
                      (Module, Kernel, Has_Multiline_Selection);
               begin
                  if Search /= No_Search then
                     Dummy := View.Context_Combo.Set_Active_Id
                       (Search.Label.all);
                  end if;
               end;
            end if;
         else
            Dummy := View.Context_Combo.Set_Active_Id (Context.all);
         end if;

         Grab_Toplevel_Focus (Get_MDI (Kernel), View.Pattern_Combo.Get_Child);
      end if;

      --  Set the mode of the search view
      View.Set_Vsearch_Mode (Mode => Mode);

      return View;
   end Get_Or_Create_Vsearch;

   ----------------------
   -- Substitute_Label --
   ----------------------

   function Substitute_Label
     (Kernel : not null access GPS.Kernel.Kernel_Handle_Record'Class;
      Label  : String) return String
   is
      function Substitution (Param : String; Quoted : Boolean) return String;
      function Substitution (Param : String; Quoted : Boolean) return String is
         pragma Unreferenced (Quoted);
      begin
         if Param = "p" then
            declare
               P : constant Project_Type_Array :=
                 Get_Selected_Project (Kernel);
               Result : Unbounded_String;
            begin
               if P'Length = 0 then
                  return Get_Project (Kernel).Name;
               else
                  for P2 in P'Range loop
                     if Result /= Null_Unbounded_String then
                        Append (Result, ", ");
                     end if;
                     Append (Result, P (P2).Name);
                  end loop;
                  return To_String (Result);
               end if;
            end;
         end if;
         return "%" & Param;
      end Substitution;
   begin
      return GNATCOLL.Templates.Substitute
        (Label,
         Delimiter => '%',
         Callback  => Substitution'Unrestricted_Access,
         Recursive => False);
   end Substitute_Label;

   --------------------------
   -- Set_Selected_Project --
   --------------------------

   procedure Set_Selected_Project
     (Kernel  : not null access Kernel_Handle_Record'Class;
      Context : Selection_Context)
   is
      View : constant Vsearch_Access := Search_Views.Retrieve_View (Kernel);
      Set : File_Info_Set;
      Idx : Integer;
   begin
      if View = null then
         return;
      end if;

      Free (View.Projects);

      if Has_Project_Information (Context) then
         View.Projects :=
           new Project_Type_Array'(1 .. 1 => Project_Information (Context));
      elsif Has_File_Information (Context) then
         Set := Get_Project_Tree (Kernel).Info_Set
           (File_Information (Context));

         if not Set.Is_Empty then
            View.Projects := new Project_Type_Array
              (1 .. Integer (Set.Length));
            Idx := 1;

            for P of Set loop
               declare
                  F_Info : constant File_Info'Class := File_Info'Class (P);
               begin
                  View.Projects (Idx) := F_Info.Project;
               end;
               Idx := Idx + 1;
            end loop;
         end if;
      end if;

      Refresh_Context_Combo (Kernel);
   end Set_Selected_Project;

   --------------------------
   -- Get_Selected_Project --
   --------------------------

   function Get_Selected_Project
     (Kernel : access GPS.Kernel.Kernel_Handle_Record'Class)
      return Project_Type_Array
   is
      View : constant Vsearch_Access := Search_Views.Retrieve_View (Kernel);
   begin
      if View = null or else View.Projects = null then
         return Project_Type_Array'(1 .. 0 => No_Project);
      else
         return View.Projects.all;
      end if;
   end Get_Selected_Project;

   -------------------
   -- Get_Selection --
   -------------------

   procedure Get_Selection
     (Kernel : access GPS.Kernel.Kernel_Handle_Record'Class;
      From   : out Gtk_Text_Mark;
      To     : out Gtk_Text_Mark)
   is
      View : constant Vsearch_Access := Search_Views.Retrieve_View (Kernel);
   begin
      if View /= null then
         From := View.Selection_From;
         To   := View.Selection_To;
      end if;
   end Get_Selection;

   ------------------------------
   -- Filter_Matches_Primitive --
   ------------------------------

   overriding function Filter_Matches_Primitive
     (Filter  : access Has_Search_Filter;
      Context : GPS.Kernel.Selection_Context) return Boolean
   is
      pragma Unreferenced (Filter, Context);
   begin
      return Vsearch_Module_Id.Search_Started;
   end Filter_Matches_Primitive;

   -------------
   -- Execute --
   -------------

   overriding function Execute
     (Command : access Find_Next_Command;
      Context : Interactive_Command_Context) return Command_Return_Type
   is
      pragma Unreferenced (Command);
      View : constant Vsearch_Access := Search_Views.Retrieve_View
        (Get_Kernel (Context.Context));
   begin
      if View /= null then
         On_Search (View);
      end if;
      return Commands.Success;
   end Execute;

   -------------
   -- Execute --
   -------------

   overriding function Execute
     (Command : access Find_Previous_Command;
      Context : Interactive_Command_Context) return Command_Return_Type
   is
      pragma Unreferenced (Command);
      View : constant Vsearch_Access := Search_Views.Retrieve_View
        (Get_Kernel (Context.Context));
   begin
      if View /= null then
         On_Search_Previous (View);
      end if;
      return Commands.Success;
   end Execute;

   --------------------
   -- Primitive_Free --
   --------------------

   overriding procedure Primitive_Free
     (Action : in out Search_Specific_Context) is
   begin
      Free (Action.Context);
   end Primitive_Free;

   -------------
   -- Execute --
   -------------

   overriding function Execute
     (Action  : access Search_Specific_Context;
      Context : Interactive_Command_Context) return Command_Return_Type
   is
      Vsearch : Vsearch_Access;
      pragma Unreferenced (Vsearch);
   begin
      Vsearch := Get_Or_Create_Vsearch
        (Get_Kernel (Context.Context),
         Raise_Widget  => True,
         Reset_Entries => True,
         Context       => Action.Context,
         Mode          => Find_Only);
      return Success;
   end Execute;

   -------------
   -- Execute --
   -------------

   overriding function Execute
     (Action  : access Replace_Specific_Context;
      Context : Interactive_Command_Context) return Command_Return_Type
   is
      Vsearch : Vsearch_Access;
      pragma Unreferenced (Vsearch);
   begin
      Vsearch := Get_Or_Create_Vsearch
        (Get_Kernel (Context.Context),
         Raise_Widget  => True,
         Reset_Entries => True,
         Context       => Action.Context,
         Mode          => Find_And_Replace);
      return Success;
   end Execute;

   ------------------------------
   -- Register_Search_Function --
   ------------------------------

   procedure Register_Search_Function
     (Kernel       : access GPS.Kernel.Kernel_Handle_Record'Class;
      Label        : String;
      Factory      : Find_Utils.Module_Search_Context_Factory;
      Selector     : access Scope_Selector_Interface'Class := null;
      Id           : access GPS.Kernel.Abstract_Module_ID_Record'Class := null;
      Mask         : Search_Options_Mask := All_Options;
      In_Selection : Boolean := False)
   is
      Data : constant Search_Module_Data :=
        Search_Module_Data'
          (Label         => new String'(Label),
           Factory       => Factory,
           Selector      => Selector,
           Id            => Module_ID (Id),
           Mask          => Mask,
           In_Selection  => In_Selection);
   begin
      if Id /= null then
         Create_New_Key_If_Necessary
           (Get_History (Kernel).all,
            Last_Function_In_Module_Key & History_Key (Get_Name (Data.Id)),
            Key_Type => Strings);
         Set_Max_Length
           (Get_History (Kernel).all,
            1,   --  Only the last one is interesting
            Last_Function_In_Module_Key & History_Key (Get_Name (Data.Id)));
      end if;

      Prepend (Vsearch_Module_Id.Search_Modules, Data);

      if Data.Selector /= null then
         declare
            Scope_Combo    : constant Gtk_Widget := Gtk_Widget
              (Data.Selector.Get_Scope_Combo);
            Scope_Optional : constant Gtk_Widget :=
                               Data.Selector.Get_Optional_Widget;
         begin
            --  Make sure the extra information is not destroyed for the
            --  duration of GPS, even when the search window is destroyed
            --  (since the same extra info widget will be reused for the next
            --  search window, to preserve the current values).
            Scope_Combo.Ref_Sink;

            --  Since the same widget could be shared amongst several search
            --  contexts, we should own one extra ref for each search context
            Scope_Combo.Ref;

            if Scope_Optional /= null then
               Scope_Optional.Ref_Sink;
               Scope_Optional.Ref;
            end if;
         end;
      end if;

      Register_Action
        (Kernel,
         Name        => -"Search in context: " & Label,
         Command     => new Search_Specific_Context'
           (Interactive_Command with Context => new String'(Label)),
         Description => -("Open the search dialog, and preset the ""Look In"""
           & " field to """ & Label & """"),
         Category    => -"Search");

      Search_Functions_Changed_Hook.Run (Kernel);
   end Register_Search_Function;

   ---------------------------
   -- Get_Nth_Search_Module --
   ---------------------------

   function Get_Nth_Search_Module
     (Kernel : access GPS.Kernel.Kernel_Handle_Record'Class;
      Num    : Positive) return Search_Module_Data
   is
      pragma Unreferenced (Kernel);
      Node : Search_Modules_List.Cursor :=
        Vsearch_Module_Id.Search_Modules.First;
   begin
      for N in 1 .. Num - 1 loop
         Node := Next (Node);
      end loop;

      if Has_Element (Node) then
         return Element (Node);
      end if;

      return No_Search;
   end Get_Nth_Search_Module;

   -----------------
   -- Find_Module --
   -----------------

   function Find_Module
     (Kernel : access Kernel_Handle_Record'Class;
      Label  : String) return Search_Module_Data
   is
      pragma Unreferenced (Kernel);
   begin
      for M of Vsearch_Module_Id.Search_Modules loop
         if M.Label.all = Label then
            return M;
         end if;
      end loop;
      return No_Search;
   end Find_Module;

   --------------------------------
   -- Search_Context_From_Module --
   --------------------------------

   function Search_Context_From_Module
     (Id           : not null access Module_ID_Record'Class;
      Handle       : access Kernel_Handle_Record'Class;
      In_Selection : Boolean := False) return Search_Module_Data
   is
      List : Cursor := Vsearch_Module_Id.Search_Modules.First;
      Last_Matching_Node : Cursor := No_Element;
      Key : constant History_Key :=
        Last_Function_In_Module_Key & History_Key (Get_Name (Module_ID (Id)));
      Last_Selected : constant String_List_Access :=
        Get_History (Get_History (Handle).all, Key);

   begin
      while Has_Element (List) loop
         if Element (List).Id = Module_ID (Id)
           and Element (List).In_Selection = In_Selection
         then
            Last_Matching_Node := List;

            if not Get_Pref (Keep_Previous_Search_Context)
              or else Last_Selected = null
              or else Last_Selected (Last_Selected'First).all =
                 Element (List).Label.all
            then
               if Active (Me) then
                  Trace (Me, "Get last search function for module "
                         & String (Key) & ": " & Element (List).Label.all);
               end if;

               return Element (List);
            end if;
         end if;

         List := Next (List);
      end loop;

      if Has_Element (Last_Matching_Node) then
         return Element (Last_Matching_Node);
      end if;

      return No_Search;
   end Search_Context_From_Module;

   ------------------------
   -- Set_Last_Of_Module --
   ------------------------

   procedure Set_Last_Of_Module
     (Handle      : access Kernel_Handle_Record'Class;
      Search_Data : Search_Module_Data) is
   begin
      if not Get_Pref (Keep_Previous_Search_Context)
        or else Search_Data.Id = null
      then
         return;
      end if;

      if Active (Me) then
         Trace (Me, "Set last search function for module "
                & Get_Name (Search_Data.Id)
                & " to " & Search_Data.Label.all);
      end if;

      Add_To_History
        (Get_History (Handle).all,
         Last_Function_In_Module_Key & History_Key (Get_Name (Search_Data.Id)),
         Search_Data.Label.all);
   end Set_Last_Of_Module;

   -----------------------------
   -- Register_Default_Search --
   -----------------------------

   procedure Register_Default_Search
     (Kernel : access GPS.Kernel.Kernel_Handle_Record'Class) is
   begin
      Register_Search_Pattern
        (Kernel,
         Name           => -"Simple string",
         Regexp         => "",
         Case_Sensitive => False,
         Is_Regexp      => False);
      Register_Search_Pattern
        (Kernel,
         Name           => -"Regular expression",
         Regexp         => "",
         Case_Sensitive => False,
         Is_Regexp      => True);
   end Register_Default_Search;

   -----------------------------
   -- Register_Search_Pattern --
   -----------------------------

   procedure Register_Search_Pattern
     (Kernel         : access Kernel_Handle_Record'Class;
      Name           : String;
      Regexp         : String;
      Case_Sensitive : Boolean := False;
      Is_Regexp      : Boolean := True)
   is
      Tmp : Search_Regexps_Array_Access := Vsearch_Module_Id.Search_Regexps;
   begin
      if Tmp /= null then
         Vsearch_Module_Id.Search_Regexps :=
           new Search_Regexps_Array (Tmp'First .. Tmp'Last + 1);
         Vsearch_Module_Id.Search_Regexps (Tmp'Range) := Tmp.all;
         Unchecked_Free (Tmp);
      else
         Vsearch_Module_Id.Search_Regexps := new Search_Regexps_Array (1 .. 1);
      end if;

      Tmp := Vsearch_Module_Id.Search_Regexps;
      Tmp (Tmp'Last) :=
        (Name           => new String'(Name),
         Regexp         => new String'(Regexp),
         Case_Sensitive => Case_Sensitive,
         Is_Regexp      => Is_Regexp);

      Search_Regexps_Changed_Hook.Run (Kernel);
   end Register_Search_Pattern;

   ---------------
   -- Customize --
   ---------------

   overriding procedure Customize
     (Module : access Vsearch_Module_Record;
      File   : GNATCOLL.VFS.Virtual_File;
      Node   : Node_Ptr;
      Level  : Customization_Level)
   is
      pragma Unreferenced (Level, File);
      Patt, Name : Node_Ptr;
   begin
      if Node.Tag.all = "vsearch-pattern" then
         Name := Find_Tag (Node.Child, "name");
         Patt := Find_Tag (Node.Child, "regexp");
         if Patt = null then
            Patt := Find_Tag (Node.Child, "string");
         end if;

         if Patt /= null and then Name /= null then
            Register_Search_Pattern
              (Kernel         => Get_Kernel (Module.all),
               Name           => Name.Value.all,
               Regexp         => Patt.Value.all,
               Case_Sensitive =>
                 To_Lower (Get_Attribute (Patt, "case-sensitive")) = "true",
               Is_Regexp      => Patt.Tag.all = "regexp");
         end if;
      end if;
   end Customize;

   ---------------------
   -- Register_Module --
   ---------------------

   procedure Register_Module
     (Kernel : access GPS.Kernel.Kernel_Handle_Record'Class)
   is
      Filter  : Action_Filter;
   begin
      Vsearch_Module_Id := new Vsearch_Module_Record;
      Search_Views.Register_Module (Kernel, Module_ID (Vsearch_Module_Id));

      Register_Action
        (Kernel, "Search",
         new Search_Specific_Context'
           (Interactive_Command with Context => null),
         Description => -("Open the search dialog. If you have selected the"
           & " preference Search/Preserve Search Context, the same context"
           & " will be selected, otherwise the context is reset depending on"
           & " the active window"),
         Icon_Name   => "gps-search-symbolic",
         Category    => -"Search");

      Register_Action
        (Kernel, "Replace",
         new Replace_Specific_Context'
           (Interactive_Command with Context => null),
         Description => -("Open the search dialog in the replace mode."
           & " If you have selected the"
           & " preference Search/Preserve Search Context, the same context"
           & " will be selected, otherwise the context is reset depending on"
           & " the active window"),
         Icon_Name   => "gps-search-symbolic",
         Category    => -"Search");

      Filter  := new Has_Search_Filter;
      Register_Action
        (Kernel, "find next", new Find_Next_Command,
         Description => -"Find the next occurrence of the search pattern",
         Filter      => Filter);

      Register_Action
        (Kernel, "find previous", new Find_Previous_Command,
         Description => -"Find the previous occurrence of the search pattern",
         Filter      => Filter);

      --  Register the default search functions

      Register_Default_Search (Kernel);

      Register_Preferences (Kernel);
   end Register_Module;

   --------------------------
   -- Register_Preferences --
   --------------------------

   procedure Register_Preferences
     (Kernel : access Kernel_Handle_Record'Class) is
   begin
      Select_On_Match := Create
        (Get_Preferences (Kernel),
         Name    => "Search-Select-On-Match",
         Label   => -"Select on match",
         Path    => -":Search",
         Doc     =>
           -"When a match is found, give the focus to the matching editor. If"
         & " unselected, the focus is left on the search window, which means"
         & " you can keep typing Enter to go to the next search, but can't"
         & " modify the editor directly",
         Default => False);

      Close_On_Match := Create
        (Get_Preferences (Kernel),
         Name    => "Search-Close-On-Match",
         Label   => -"Close on match",
         Path    => -":Search",
         Doc     =>
           -"If this is selected, the search dialog is closed when a match is"
         & " found. You can still search for the next occurrence by using"
         & " the appropriate shortcut (Ctrl-N by default)",
         Default => False);

      Ask_Confirmation_For_Replace_All := Create
        (Get_Preferences (Kernel),
         Name  => "Ask-Confirmation-For-Replace-All",
         Label => -"Confirmation for 'Replace all'",
         Path  => -":Search",
         Doc   =>
            -"Enable the confirmation popup before a replace all operation.",
         Default => True);

      Keep_Previous_Search_Context := Create
        (Get_Preferences (Kernel),
         Name  => "keep-previous-search-context",
         Label => -"Preserve Search Context",
         Path  => -":Search",
         Doc   => -("Preserve the contents of the ""Look in"" entry"
           & " between searches."),
         Default => False);
   end Register_Preferences;

   ------------------
   -- Reset_Search --
   ------------------

   procedure Reset_Search
     (Object : access Glib.Object.GObject_Record'Class;
      Kernel : GPS.Kernel.Kernel_Handle)
   is
      pragma Unreferenced (Object);
   begin
      --  Call this to avoid dangling pointers in View.Projects
      Set_Selected_Project (Kernel, Kernel.Get_Current_Context);
      Search_Reset_Hook.Run (Kernel);
   end Reset_Search;

end Vsearch;
