-----------------------------------------------------------------------
--                               G P S                               --
--                                                                   --
--                  Copyright (C) 2001-2009, AdaCore                 --
--                                                                   --
-- GPS is free  software;  you can redistribute it and/or modify  it --
-- under the terms of the GNU General Public License as published by --
-- the Free Software Foundation; either version 2 of the License, or --
-- (at your option) any later version.                               --
--                                                                   --
-- This program is  distributed in the hope that it will be  useful, --
-- but  WITHOUT ANY WARRANTY;  without even the  implied warranty of --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU --
-- General Public License for more details. You should have received --
-- a copy of the GNU General Public License along with this program; --
-- if not,  write to the  Free Software Foundation, Inc.,  59 Temple --
-- Place - Suite 330, Boston, MA 02111-1307, USA.                    --
-----------------------------------------------------------------------

with Gdk.Color;    use Gdk.Color;
with Gtk;          use Gtk;
with Gtk.Text_Tag; use Gtk.Text_Tag;
with Gtk.Widget;   use Gtk.Widget;
with Pango.Font;   use Pango.Font;

with Language;     use Language;

package body Src_Highlighting is

   -----------
   -- Unref --
   -----------

   procedure Unref (Tags : in out Highlighting_Tags) is
   begin
      for T in Tags'Range loop
         if Tags (T) /= null then
            Unref (Tags (T));
            Tags (T) := null;
         end if;
      end loop;
   end Unref;

   --------------------------
   -- Forward_Declarations --
   --------------------------

   procedure New_Tag
     (Tag        : out Gtk.Text_Tag.Gtk_Text_Tag;
      Tag_Name   : String;
      Fore_Color : Gdk_Color := Null_Color;
      Back_Color : Gdk_Color := Null_Color;
      Font_Desc  : Pango_Font_Description := null);
   --  Create a new Gtk_Text_Tag with the given name.
   --  If the tag already exists, its properties are changed accordingly.

   -------------
   -- New_Tag --
   -------------

   procedure New_Tag
     (Tag        : out Gtk.Text_Tag.Gtk_Text_Tag;
      Tag_Name   : String;
      Fore_Color : Gdk_Color := Null_Color;
      Back_Color : Gdk_Color := Null_Color;
      Font_Desc  : Pango_Font_Description := null) is
   begin
      if Tag = null then
         Gtk_New (Tag, Tag_Name);
      end if;

      if Font_Desc /= null then
         Set_Property (Tag, Text_Tag.Font_Desc_Property, Font_Desc);
      end if;

      if Fore_Color /= White (Get_Default_Colormap) then
         Set_Property (Tag, Foreground_Gdk_Property, Fore_Color);
      else
         Set_Property (Tag, Foreground_Gdk_Property, Null_Color);
      end if;

      if Back_Color /= White (Get_Default_Colormap) then
         Set_Property (Tag, Background_Gdk_Property, Back_Color);
      else
         Set_Property (Tag, Background_Gdk_Property, Null_Color);
      end if;
   end New_Tag;

   ------------------------
   -- Create_Syntax_Tags --
   ------------------------

   procedure Create_Syntax_Tags
     (Result                      : in out Highlighting_Tags;
      Keyword_Color               : Gdk.Color.Gdk_Color;
      Keyword_Color_Bg            : Gdk.Color.Gdk_Color;
      Keyword_Font_Desc           : Pango.Font.Pango_Font_Description := null;
      Comment_Color               : Gdk.Color.Gdk_Color;
      Comment_Color_Bg            : Gdk.Color.Gdk_Color;
      Comment_Font_Desc           : Pango.Font.Pango_Font_Description := null;
      Annotated_Comment_Color     : Gdk.Color.Gdk_Color;
      Annotated_Comment_Color_Bg  : Gdk.Color.Gdk_Color;
      Annotated_Comment_Font_Desc : Pango.Font.Pango_Font_Description := null;
      Character_Color             : Gdk.Color.Gdk_Color;
      Character_Color_Bg          : Gdk.Color.Gdk_Color;
      Character_Font_Desc         : Pango.Font.Pango_Font_Description := null;
      String_Color                : Gdk.Color.Gdk_Color;
      String_Color_Bg             : Gdk.Color.Gdk_Color;
      String_Font_Desc            : Pango.Font.Pango_Font_Description := null)
   is
   begin
      New_Tag
        (Result (Keyword_Text),
         Keyword_Color_Tag_Name,
         Fore_Color => Keyword_Color,
         Back_Color => Keyword_Color_Bg,
         Font_Desc  => Keyword_Font_Desc);
      New_Tag
        (Result (Comment_Text),
         Comment_Color_Tag_Name,
         Fore_Color => Comment_Color,
         Back_Color => Comment_Color_Bg,
         Font_Desc  => Comment_Font_Desc);
      New_Tag
        (Result (Annotated_Comment_Text),
         Annotated_Comment_Color_Tag_Name,
         Fore_Color => Annotated_Comment_Color,
         Back_Color => Annotated_Comment_Color_Bg,
         Font_Desc  => Annotated_Comment_Font_Desc);
      New_Tag
        (Result (String_Text),
         String_Color_Tag_Name,
         Fore_Color => String_Color,
         Back_Color => String_Color_Bg,
         Font_Desc  => String_Font_Desc);
      New_Tag
        (Result (Character_Text),
         Character_Color_Tag_Name,
         Fore_Color => Character_Color,
         Back_Color => Character_Color_Bg,
         Font_Desc  => Character_Font_Desc);
      --  ??? Set the tags priority...
   end Create_Syntax_Tags;

   -------------------------------
   -- Create_Highlight_Line_Tag --
   -------------------------------

   procedure Create_Highlight_Line_Tag
     (Tag   : out Gtk.Text_Tag.Gtk_Text_Tag;
      Color : Gdk_Color) is
   begin
      New_Tag (Tag, Highlight_Line_Tag_Name, Back_Color => Color);
      --  ??? Set the tag priority...
   end Create_Highlight_Line_Tag;

end Src_Highlighting;
