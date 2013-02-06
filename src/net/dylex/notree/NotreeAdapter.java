package net.dylex.notree;

import net.dylex.notree.NotreeStore;

import android.content.Context;
import android.database.Cursor;
import android.graphics.Typeface;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.CursorTreeAdapter;
import android.widget.ImageButton;
import android.widget.TextView;
import android.util.Log;

class NotreeAdapter extends CursorTreeAdapter 
{
	private static final String TAG = "NotreeAdapter";

	protected Notree mActivity;
	private LayoutInflater mInflate;

	public NotreeAdapter(Cursor cursor, Notree activity)
	{
		super(cursor, activity);
		mActivity = activity;
		mInflate = activity.getLayoutInflater();
	}

	@Override
	protected Cursor getChildrenCursor(Cursor groupCursor)
	{
		final long id = groupCursor.getLong(0);
		if (id == mActivity.getCurrentId())
			return mActivity.getBodyCursor();
		else
			return mActivity.getNoteCursor(id);
	}

	@Override
	protected View newGroupView(Context context, Cursor cursor, boolean isExpanded, ViewGroup parent)
	{
		return mInflate.inflate(R.layout.item_group, parent, false);
	}

	@Override
	protected View newChildView(Context context, Cursor cursor, boolean isLastChild, ViewGroup parent)
	{
		TextView view = new TextView(context);
		return view;
	}

	@Override
	protected void bindGroupView(View view, Context context, Cursor cursor, boolean isExpanded)
	{
		final long id = cursor.getLong(0);

		TextView title = (TextView)view.findViewById(R.id.title);
		title.setText(cursor.getString(1));
		if (id == mActivity.getCurrentId())
		{
			title.setTypeface(Typeface.DEFAULT_BOLD);
			title.setClickable(false);
		}
		else
		{
			title.setTypeface(Typeface.DEFAULT);
			title.setOnClickListener(new View.OnClickListener() {
				public void onClick(View v) {
					Log.d(TAG, "click group " + id);
					mActivity.setParent(id);
				}
			});
		}
	}

	@Override
	protected void bindChildView(View view, Context context, Cursor cursor, boolean isLastChild)
	{
		((TextView)view).setText(cursor.getString(1));
		if (cursor.getColumnName(1).equals("body"))
			((TextView)view).setTypeface(Typeface.MONOSPACE);
	}
}
