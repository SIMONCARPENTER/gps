------------------------------------------------------------------------------
--                                                                          --
--                         GNAT COMPILER COMPONENTS                         --
--                                                                          --
--                      Make_Test_Window_Pkg.Callbacks                      --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--                            $Revision$
--                                                                          --
--                Copyright (C) 2001 Ada Core Technologies, Inc.            --
--                                                                          --
-- GNAT is free software;  you can  redistribute it  and/or modify it under --
-- terms of the  GNU General Public License as published  by the Free Soft- --
-- ware  Foundation;  either version 2,  or (at your option) any later ver- --
-- sion.  GNAT is distributed in the hope that it will be useful, but WITH- --
-- OUT ANY WARRANTY;  without even the  implied warranty of MERCHANTABILITY --
-- or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License --
-- for  more details.  You should have  received  a copy of the GNU General --
-- Public License  distributed with GNAT;  see file COPYING.  If not, write --
-- to  the Free Software Foundation,  59 Temple Place - Suite 330,  Boston, --
-- MA 02111-1307, USA.                                                      --
--                                                                          --
-- GNAT is maintained by Ada Core Technologies Inc (http://www.gnat.com).   --
--                                                                          --
------------------------------------------------------------------------------

with Ada.Text_IO;             use Ada.Text_IO;
with Ada.Characters.Handling; use Ada.Characters.Handling;

with Gtk.GEntry;              use Gtk.GEntry;
with Gtk.Widget;              use Gtk.Widget;
with Gtk.Main;                use Gtk.Main;
with String_Utils;            use String_Utils;

with Gtkada.Dialogs;          use Gtkada.Dialogs;
with GNAT.OS_Lib;             use GNAT.OS_Lib;

package body Make_Test_Window_Pkg.Callbacks is
   --  Handle callbacks from "AUnit_Make_Test" main window.  Template
   --  generated by Glade

   ---------------------------------------
   -- On_Make_Test_Window_Delete_Event --
   ---------------------------------------

   function On_Make_Test_Window_Delete_Event
     (Object : access Gtk_Widget_Record'Class;
      Params : Gtk.Arguments.Gtk_Args) return Boolean
   is
   begin
      Main_Quit;
      return True;
   end On_Make_Test_Window_Delete_Event;

   ----------------------------
   -- On_Name_Entry_Activate --
   ----------------------------

   procedure On_Name_Entry_Activate
     (Object : access Gtk_Entry_Record'Class)
   is
      Window : Make_Test_Window_Access
        := Make_Test_Window_Access (Get_Toplevel (Object));
   begin
      Grab_Focus (Window.Description_Entry);
   end On_Name_Entry_Activate;

   -----------------------------------
   -- On_Description_Entry_Activate --
   -----------------------------------

   procedure On_Description_Entry_Activate
     (Object : access Gtk_Entry_Record'Class)
   is
      Window : Make_Test_Window_Access
        := Make_Test_Window_Access (Get_Toplevel (Object));
   begin
      Grab_Focus (Window.Ok);
   end On_Description_Entry_Activate;

   -------------------
   -- On_Ok_Clicked --
   -------------------

   procedure On_Ok_Clicked
     (Object : access Gtk_Button_Record'Class)
   is
      --  Generate "Test_Case" source files.  Exit program if successful

      Window : Make_Test_Window_Access :=
        Make_Test_Window_Access (Get_Toplevel (Object));
      File   : File_Type;
      Name   : String := Get_Text (Window.Name_Entry);
      Description : String := Get_Text (Window.Description_Entry);
   begin
      if Name /= "" then
         if To_Lower (Name) = "test_case" then
            if Message_Dialog
              ("The name of the test cannot be ""Test_Case""."
               & ASCII.LF & "Write the code anyways ?",
               Warning,
               Button_Yes or Button_No,
               Button_No,
               "",
               "Warning !") = Button_No
            then
               return;
            end if;
         end if;

         if Is_Regular_File (To_File_Name (Name) & ".ads") then
            if Message_Dialog
              ("File " & To_File_Name (Name) & ".ads" & " exists. Overwrite?",
               Warning,
               Button_Yes or Button_No,
               Button_No,
               "",
               "Warning !") = Button_No
            then
               return;
            end if;
         end if;

         --  Correct the case for Name, if needed.

         Mixed_Case (Name);

         --  Create the file.

         Create (File, Out_File, To_File_Name (Name) & ".ads");
         Put_Line (File,
                   "with Ada.Strings.Unbounded;" & ASCII.LF &
                   "use Ada.Strings.Unbounded;" & ASCII.LF &
                   ASCII.LF &
                   "with AUnit.Test_Cases;" & ASCII.LF &
                   "use AUnit.Test_Cases;" & ASCII.LF &
                   ASCII.LF &
                   "package " & Name & " is" & ASCII.LF &
                   ASCII.LF &
                   "   type Test_Case is new " &
                   "AUnit.Test_Cases.Test_Case with null record;" & ASCII.LF &
                   ASCII.LF &
                   "   --  Register routines to be run:" & ASCII.LF &
                   "   procedure Register_Tests (T : in out Test_Case);"
                   & ASCII.LF &
                   ASCII.LF &
                   "   --  Provide name identifying the test case:"
                   & ASCII.LF &
                   "   function Name (T : Test_Case) return String_Access;");
         if Get_Active (Window.Override_Set_Up) then
            Put_Line (File,
                      ASCII.LF &
                      "   --  Preparation performed before each routine:"
                      & ASCII.LF &
                      "   procedure Set_Up (T : in out Test_Case);");
         end if;
         if Get_Active (Window.Override_Tear_Down) then
            Put_Line (File,
                      ASCII.LF &
                      "   --  Cleanup performed after each routine:"
                      & ASCII.LF &
                      "   procedure Tear_Down (T :  in out Test_Case);");
         end if;
         Put_Line (File,
                   ASCII.LF &
                   "end " & Name & ";" & ASCII.LF);
         Close (File);

         if Is_Regular_File (To_File_Name (Name) & ".adb") then
            if Message_Dialog
              ("File " & To_File_Name (Name) & ".adb" & " exists. Overwrite?",
               Warning,
               Button_Yes or Button_No,
               Button_No,
               "",
               "Warning !") = Button_No
            then
               return;
            end if;
         end if;

         Create (File, Out_File, To_File_Name (Name) & ".adb");
         Put_Line (File,
                   "with AUnit.Test_Cases.Registration;" & ASCII.LF &
                   "use AUnit.Test_Cases.Registration;" & ASCII.LF &
                   ASCII.LF &
                   "with AUnit.Assertions; use AUnit.Assertions;" & ASCII.LF &
                   ASCII.LF &
                   "package body " & Name & " is" & ASCII.LF);
         if Get_Active (Window.Override_Set_Up) then
            Put_Line (File,
                      ASCII.LF &
                      "   ------------" & ASCII.LF &
                      "   -- Set_Up --" & ASCII.LF &
                      "   ------------" & ASCII.LF &
                      ASCII.LF &
                      "   procedure Set_Up (T : in out Test_Case) is"
                      & ASCII.LF &
                      "   begin" & ASCII.LF &
                      "      null;" & ASCII.LF &
                      "   end Set_Up;");
         end if;
         if Get_Active (Window.Override_Tear_Down) then
            Put_Line (File,
                      ASCII.LF &
                      "   ---------------" & ASCII.LF &
                      "   -- Tear_Down --" & ASCII.LF &
                      "   ---------------" & ASCII.LF &
                      ASCII.LF &
                      "   procedure Tear_Down (T : in out Test_Case) is"
                      & ASCII.LF &
                      "   begin" & ASCII.LF &
                      "      null;" & ASCII.LF &
                      "   end Tear_Down;" & ASCII.LF);
         end if;
            Put_Line (File,
                      ASCII.LF &
                      "   -------------------" & ASCII.LF &
                      "   -- Test Routines --" & ASCII.LF &
                      "   -------------------" & ASCII.LF &
                      ASCII.LF &
                      ASCII.LF &
                   "   procedure Register_Tests (T : in out Test_Case) is"
                   &  ASCII.LF &
                   "   begin" & ASCII.LF &
                   "      null;" & ASCII.LF &
                   "   end Register_Tests;" & ASCII.LF &
                   ASCII.LF & -- ASCII.LF &
                   "   --  Identifier of test case:" & ASCII.LF &
                   "   function Name (T : Test_Case) return String_Access is"
                   & ASCII.LF &
                   "   begin" & ASCII.LF &
                   "      return new String'(" & '"'
                   & Strip_Quotes (Description)
                   & '"' & ");"
                   & ASCII.LF &
                   "   end Name;" & ASCII.LF &
                   ASCII.LF &
                   "end " & Name & ";");

         Close (File);
         Put (Standard_Output, To_File_Name (Name));
      end if;

      Destroy (Window);
      Main_Quit;
   end On_Ok_Clicked;

   -----------------------
   -- On_Cancel_Clicked --
   -----------------------

   procedure On_Cancel_Clicked
     (Object : access Gtk_Button_Record'Class)
   is
   begin
      Destroy (Get_Toplevel (Object));
      Main_Quit;
   end On_Cancel_Clicked;

   ---------------------
   -- On_Help_Clicked --
   ---------------------

   procedure On_Help_Clicked
     (Object : access Gtk_Button_Record'Class)
   is
   begin
      null;
   end On_Help_Clicked;

end Make_Test_Window_Pkg.Callbacks;
