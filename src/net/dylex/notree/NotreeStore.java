package net.dylex.notree;

import android.content.ContentUris;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteOpenHelper;
import android.net.Uri;
import android.util.Log;

class NotreeStore extends SQLiteOpenHelper 
{
	private static final String TAG = "NotreeStore";
	private static final String TABLE = "notree";

	public static final long NULL_ID = 0;

	public NotreeStore(Context context) {
		super(context, "notree.db", null, 1);
	}

	@Override
	public void onCreate(SQLiteDatabase db)
	{
		db.execSQL("CREATE TABLE " + TABLE + " "
				+ "(_id INTEGER PRIMARY KEY"
				+ ",_dirty INTEGER NOT NULL DEFAULT 0"
				+ ",parent INTEGER NOT NULL REFERENCES notree"
				+ ",created INTEGER NOT NULL"
				+ ",modified INTEGER"
				+ ",title TEXT NOT NULL"
				+ ",body TEXT"
				+ ")");
		db.execSQL("CREATE TRIGGER notree_recurse_delete DELETE ON " + TABLE + " BEGIN"
				+ " DELETE FROM " + TABLE + " WHERE parent = OLD._id; "
				+ "END");
	}

	@Override
	public void onUpgrade(SQLiteDatabase db, int v0, int v1)
	{
		db.execSQL("DROP TABLE IF EXISTS notree");
		db.execSQL("DROP TRIGGER IF EXISTS notree_recurse_delete");
		onCreate(db);
	}

	public static class Note {
		protected long id = NULL_ID;
		protected long parent = NULL_ID;
		protected long created;
		protected Long modified = null;
		protected String title = "";
		protected String body = null;

		protected Note(Cursor c)
		{
			c.moveToNext();
			int i = 0;
			id = c.getLong(i);
			i++; // dirty
			if (!c.isNull(++i))
				parent = c.getLong(i);
			created = c.getLong(++i);
			if (!c.isNull(++i))
				modified = new Long(c.getLong(i));
			title = c.getString(++i);
			if (!c.isNull(++i))
				body = c.getString(i);
		}

		public Note(long parent)
		{
			this.parent = parent;
			this.created = System.currentTimeMillis();
		}

		protected Note() { }

		public boolean isNull()
			{ return id == NULL_ID; }

		public long getId()
			{ return id; }

		public static long getId(long id)
			{ return id; }

		public static long getId(Note n)
		{
			if (n == null)
				return NULL_ID;
			else
				return n.id;
		}

		protected ContentValues contentValues()
		{
			ContentValues c = new ContentValues(8);
			c.put("_dirty", 1);
			c.put("parent", parent);
			c.put("created", created);
			c.put("modified", modified);
			c.put("title", title);
			c.put("body", body);
			return c;
		}

		static public Uri contentUri(long id)
		{
			return ContentUris.withAppendedId(Uri.parse("content://net.dylex.notree"), id);
		}

		public Uri contentUri()
			{ return contentUri(getId()); }
	};

	public Note getNote(long id)
	{
		if (id == NULL_ID)
			return new Note();
		SQLiteDatabase db = getReadableDatabase();
		Cursor c = db.query(TABLE,
				null,
				"_id = ?", 
				new String[] { String.valueOf(id) },
				null, null, null);
		Note n = null;
		if (!c.isLast())
			n = new Note(c);
		c.close();
		return n;
	}

	public Cursor getChildrenCursor(long parent) {
		SQLiteDatabase db = getReadableDatabase();
		return db.query(TABLE,
				new String[] { "_id", "title" }, 
				"parent = ? AND _dirty >= 0",
				new String[] { String.valueOf(parent) },
				null, null, null);
	}

	public Note addNote(Note n)
	{
		n.id = getWritableDatabase().insertOrThrow(TABLE, "parent", n.contentValues());
		return n;
	}

	public void setNote(Note n)
	{
		n.modified = System.currentTimeMillis();
		getWritableDatabase().update(TABLE, n.contentValues(), 
				"_id = ?", 
				new String[] { String.valueOf(n.getId()) });
	}

	public void removeNote(long id)
	{
		ContentValues c = new ContentValues(1);
		c.put("_dirty", -1);
		getWritableDatabase().update(TABLE, c,
				"_id = ?", 
				new String[] { String.valueOf(id) });
	}
}
