package net.dylex.notree;

import net.dylex.notree.NotreeStore;

import android.app.ExpandableListActivity;
import android.content.Intent;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.database.MergeCursor;
import android.os.Bundle;
import android.util.Log;
import android.view.ContextMenu;
import android.view.KeyEvent;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.widget.ExpandableListView;
import android.widget.TextView;
import java.lang.Class;

public class Notree extends ExpandableListActivity
{
	private static final String TAG = "Notree";

	private static final int MENU_ADD 	= Menu.FIRST;
	private static final int MENU_DELETE 	= Menu.FIRST+1;
	private static final int MENU_EDIT 	= Menu.FIRST+2;

	protected NotreeStore mStore;
	protected NotreeAdapter mAdapter;
	private NotreeStore.Note mCurrent;
	private TextView mBody;

	@Override
	public void onCreate(Bundle savedInstanceState)
	{
		super.onCreate(savedInstanceState);
		mStore = new NotreeStore(this);

		setContentView(R.layout.main);
		mAdapter = new NotreeAdapter(null, this);
		setListAdapter(mAdapter);

		mBody = (TextView)findViewById(R.id.body);

		Intent intent = getIntent();
		long id = NotreeStore.NULL_ID;
		if (intent.getData() != null && intent.getData().getLastPathSegment() != null)
			id = Long.valueOf(intent.getData().getLastPathSegment());

		setParent(id);

		getExpandableListView().setOnCreateContextMenuListener(this);
	}

	@Override
	public void onDestroy()
	{
		super.onDestroy();
		mStore.close();
	}

	long getCurrentId()
		{ return mCurrent.getId(); }

	Cursor getNoteCursor(long id)
	{
		Cursor cursor = mStore.getChildrenCursor(id);
		startManagingCursor(cursor);
		return cursor;
	}

	Cursor getTopCursor()
	{
		if (mCurrent.getId() == NotreeStore.NULL_ID)
			return getNoteCursor(NotreeStore.NULL_ID);
		MatrixCursor top = new MatrixCursor(new String[] { "_id", "title" }, 1);
		top.addRow(new Object[] { mCurrent.getId(), mCurrent.title });
		Cursor cursor = getNoteCursor(mCurrent.getId());
		MergeCursor all = new MergeCursor(new Cursor[] { top, cursor });
		startManagingCursor(all);
		return all;
	}

	Cursor getBodyCursor()
	{
		MatrixCursor cursor = new MatrixCursor(new String[] { "_id", "body" }, 1);
		if (mCurrent.body != null)
			cursor.addRow(new Object[] { mCurrent.getId(), mCurrent.body });
		startManagingCursor(cursor);
		return cursor;
	}

	void setParent(long parent)
	{
		mCurrent = mStore.getNote(parent);
		//setTitle(mCurrent.title);
		mAdapter.changeCursor(getTopCursor());
	}

	private void editNote(long id)
	{
		startActivity(new Intent(Intent.ACTION_EDIT, NotreeStore.Note.contentUri(id), this, NotreeEdit.class));
	}

	@Override
	public boolean onChildClick(ExpandableListView parent, View v, int groupPosition, int childPosition, long id)
	{
		if (id != getCurrentId())
		{
			setParent(id);
			return true;
		}
		return false;
	}

	@Override
	public boolean onKeyDown(int keyCode, KeyEvent event)
	{
		if (keyCode == KeyEvent.KEYCODE_BACK)
		{
			event.startTracking();
			return true;
		}
		return super.onKeyDown(keyCode, event);
	}

	@Override
	public void onBackPressed()
	{
		if (mCurrent.isNull())
			finish();
		else
			setParent(mCurrent.parent);
	}

	@Override
	public boolean onCreateOptionsMenu(Menu menu)
	{
		menu.add(0, MENU_ADD, 0, "Add")
			.setIcon(android.R.drawable.ic_menu_add);
		if (!mCurrent.isNull())
		{
			menu.add(0, MENU_EDIT, 0, "Edit")
				.setIcon(android.R.drawable.ic_menu_edit);
			menu.add(0, MENU_DELETE, 0, "Delete")
				.setIcon(android.R.drawable.ic_menu_delete);
		}
		return true;
	}

	@Override
	public boolean onOptionsItemSelected(MenuItem item) {
		switch (item.getItemId()) {
			case MENU_ADD:
				editNote(mStore.addNote(new NotreeStore.Note(mCurrent.getId())).getId());
				return true;
			case MENU_EDIT:
				editNote(mCurrent.id);
				return true;
			case MENU_DELETE:
				mStore.removeNote(mCurrent.id);
				return true;
		}
		return super.onOptionsItemSelected(item);
	}

	@Override
	public void onCreateContextMenu(ContextMenu menu, View v, ContextMenu.ContextMenuInfo menuInfo)
	{
		menu.add(0, MENU_EDIT, 0, "Edit");
		menu.add(0, MENU_DELETE, 0, "Delete");
	}

	@Override
	public boolean onContextItemSelected(MenuItem item) {
		ExpandableListView.ExpandableListContextMenuInfo info;
		try {
			info = (ExpandableListView.ExpandableListContextMenuInfo)item.getMenuInfo();
			//info.id = getCurrentId();
		} catch (ClassCastException e) {
			Log.e(TAG, "bad menuInfo", e);
			return false;
		}
		switch (item.getItemId()) {
			case MENU_EDIT:
				editNote(info.id);
				return true;
			case MENU_DELETE:
				mStore.removeNote(info.id);
				mAdapter.notifyDataSetChanged();
				return true;
		}
		return super.onContextItemSelected(item);
	}
}
