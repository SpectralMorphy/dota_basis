// import lol from `util`
// lol()
import './panorama_adapter'
import * as React from 'react'
import { render } from 'react-panorama'

let parent = $.GetContextPanel().GetParent() as Panel
render(<Label text="Hello, world!" />, parent);

$.Msg('yo')