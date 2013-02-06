package net.dylex.notree;

import net.dylex.notree.NotreeStore;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.util.Log;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;

public class NotreeEdit extends Activity 
{
	private static final String TAG = "Notree";

	private static final int MENU_REVERT = Menu.FIRST;

	protected NotreeStore mStore;
	private NotreeStore.Note mNote;
	private EditText mTitle;
	private EditText mBody;

	@Override
	public void onCreate(Bundle savedInstanceState)
	{
		super.onCreate(savedInstanceState);
		mStore = new NotreeStore(this);

		Intent intent = getIntent();
		long id;
		if (!Intent.ACTION_EDIT.equals(intent.getAction())
				|| intent.getData() == null
				|| intent.getData().getLastPathSegment() == null)
		{
			Log.e(TAG, "bad NotreeEdit action");
			finish();
			return;
		}

		id = Long.valueOf(intent.getData().getLastPathSegment());

		setContentView(R.layout.edit);

		mNote = mStore.getNote(id);

		mTitle = (EditText) findViewById(R.id.title);
		mBody = (EditText) findViewById(R.id.body);

		((Button)findViewById(R.id.save)).setOnClickListener(new View.OnClickListener() {
			public void onClick(View v) {
				save();
				finish();
			}
		});

		((Button)findViewById(R.id.cancel)).setOnClickListener(new View.OnClickListener() {
			public void onClick(View v) {
				finish();
			}
		});

		populate();
	}

	private void populate()
	{
		mTitle.setText(mNote.title);
		mBody.setText(mNote.body);
	}

	private void save()
	{
		mNote.title = mTitle.getText().toString();
		mNote.body = mBody.getText().toString();
		if (mNote.body.equals(""))
			mNote.body = null;
		mStore.setNote(mNote);
	}

	@Override
	public boolean onCreateOptionsMenu(Menu menu)
	{
		menu.add(0, MENU_REVERT, 0, "Revert")
			.setIcon(android.R.drawable.ic_menu_revert);
		return true;
	}

	@Override
	public boolean onOptionsItemSelected(MenuItem item) {
		switch (item.getItemId()) {
			case MENU_REVERT:
				populate();
				return true;
		}
		return super.onOptionsItemSelected(item);
	}

	@Override
	public void onDestroy()
	{
		super.onDestroy();
		mStore.close();
	}
}
