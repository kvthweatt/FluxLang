## Flux Language Keyword Progress

<table>
  <tr>
    <th>Keyword</th>
    <th>Status</th>
  </tr>
  <tr>
    <td>alignof</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>and</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>as</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>asm</td>
    <td>Partially Implemented ⚠️<br><br>
        Causes functions to not compile.</td>
  </tr>
  <tr>
    <td>assert</td>
    <td>Partially Implemented ⚠️<br><br>
        `codegen` missing.</td>
  </tr>
  <tr>
    <td>auto</td>
    <td>Partially Implemented ⚠️<br><br>
        Parser needs to support auto in `statement()`.</td>
  </tr>
  <tr>
    <td>bool</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>break</td>
    <td>Not Implemented ❌</td>
  </tr>
  <tr>
    <td>case</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>catch</td>
    <td>Not Implemented ❌</td>
  </tr>
  <tr>
    <td>const</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>continue</td>
    <td>Not Implemented ❌</td>
  </tr>
  <tr>
    <td>data</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>def</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>default</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>do</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>elif</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>else</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>float</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>for</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>if</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>import</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>in</td>
    <td>Not Implemented ❌
        Parser needs to recognize `if (x in y)`</td>
  </tr>
  <tr>
    <td>int</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>namespace</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>not</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>object</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>or</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>private</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>public</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>return</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>signed</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>sizeof</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>struct</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>switch</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>this</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>throw</td>
    <td>Not Implemented ❌
        `codegen` missing.</td>
  </tr>
  <tr>
    <td>try</td>
    <td>Not Implemented ❌</td>
  </tr>
  <tr>
    <td>union</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>unsigned</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>using</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>void</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>volatile</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>while</td>
    <td>Implemented ✅</td>
  </tr>
  <tr>
    <td>xor</td>
    <td>Partially Implemented ⚠️<br><br>
        Recent changes now cause issue.<br><br>
        `while(true)` not working, "Unexpected token: BOOL"</td>
  </tr>
</table>